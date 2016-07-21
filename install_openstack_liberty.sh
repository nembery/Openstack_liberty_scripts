#!/bin/bash
# script to install openstack liberty in a very generic way
# this follows the install guide from here:
# http://docs.openstack.org/liberty/install-guide-ubuntu/
# This will configure networking option 2 (self service networks)
# Pre-reqs: 
# ubuntu 14.04
# apt-get install software-properties-common
# add-apt-repository cloud-archive:liberty
# apt-get update && apt-get dist-upgrade
# apt-get install python-openstackclient
#
# nembery@gmail.com 11-17-15

if [ x$2x == xx ];
 then
  echo "usage: install_openstack_liberty.sh ip_address management_ip"
  echo "ip_address should be your data network where compute nodes connect to this control node"
  exit 1
fi

IP=$1
MGMT_IP=$2

# this is the subnet for use with a public provider network
# i.e. this should be your underlay network
NET_CIDR=10.0.1.0/24
NET_START=10.0.1.129
NET_END=10.0.1.253

# which NIC should be used for underlay network?
EXT_INTERFACE=eth0
# defaults
ADMIN_PASS=secret
DEMO_PASS=demo
# set random passwords everywhere!
MYSQL_PASS=$(openssl rand -hex 10)
NOVA_PASS=$(openssl rand -hex 10)
GLANCE_PASS=$(openssl rand -hex 10)
NEUTRON_PASS=$(openssl rand -hex 10)
HEAT_PASS=$(openssl rand -hex 10)
RABBIT_GUEST_PASS=$(openssl rand -hex 10)
RABBIT_OS_PASS=$(openssl rand -hex 10)
KEYSTONE_PASS=$(openssl rand -hex 10)

echo "Using $IP for openstack components"

function fail {
	echo "welp!"
	exit 1
}

export DEBIAN_FRONTEND=noninteractive

# copy all output to a logfile
exec > >(tee -i /var/log/openstack_install.log)
exec 2>&1

echo "--------------------------"
echo "install prereqs"
echo "--------------------------"

#apt-get update
#apt-get install software-properties-common -y || fail
#add-apt-repository cloud-archive:liberty -y || fail
#apt-get update && apt-get dist-upgrade -y || fail
apt-get install python-openstackclient -y || fail
apt-get install ntp curl openssl python-keyring -y || fail

echo "--------------------------"
echo "install mysql / mariadb"
echo "--------------------------"
apt-get install mariadb-server python-pymysql -y || fail

cat <<EOF > /etc/mysql/conf.d/mysqld_openstack.cnf
[mysqld]
bind-address = $IP
default-storage-engine = innodb
innodb_file_per_table
collation-server = utf8_general_ci
init-connect = 'SET NAMES utf8'
character-set-server = utf8
EOF

# set mysql password 
mysqladmin -u root password $MYSQL_PASS || fail

service mysql restart || fail

#maybe you should do this? I leave it off to keep everything automated
#mysql_secure_installation

echo "--------------------------"
echo " install mongodb"
echo "--------------------------"
apt-get install mongodb-server mongodb-clients python-pymongo -y || fail
sed -i.bkup -e 's/bind_ip = 127.0.0.1/bind_ip = $IP/' /etc/mongodb.conf
echo "smallfiles = true" >> /etc/mongodb.conf
service mongodb restart && sleep 3

echo "--------------------------"
echo " install rabbitmq "
echo "--------------------------"
apt-get install rabbitmq-server -y && sleep 3

echo "--------------------------"
echo " configure rabbitmq openstack user "
echo "--------------------------"
rabbitmqctl change_password guest $RABBIT_GUEST_PASS || fail
rabbitmqctl add_user openstack $RABBIT_OS_PASS || fail
rabbitmqctl set_permissions openstack ".*" ".*" ".*" || fail

echo "--------------------------"
echo " creating keystone mysql db "
echo "--------------------------"
mysqladmin -p$MYSQL_PASS create keystone || fail

mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_PASS';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_PASS';"

# generate admin_token
ADMIN_TOKEN=$(openssl rand -hex 10)

echo "--------------------------"
echo " install keystone"
echo "--------------------------"
echo "manual" > /etc/init/keystone.override
apt-get install keystone apache2 libapache2-mod-wsgi memcached python-memcache -y

cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.orig

cat <<EOF >/etc/keystone/keystone.conf
[DEFAULT]
verbose = True
admin_token = $ADMIN_TOKEN
[database]
connection = mysql+pymysql://keystone:$KEYSTONE_PASS@$IP/keystone
[memcache]
servers = localhost:11211
[extra_headers]
Distribution = Ubuntu
[token]
provider = uuid
driver = memcache
[revoke]
driver = sql
EOF

# rm /etc/init/keystone.override
su -s /bin/sh -c "keystone-manage db_sync" keystone

echo "--------------------------"
echo " Configure apache "
echo "--------------------------"
echo ServerName $IP >> /etc/apache2/apache2.conf

cat <<EOF > /etc/apache2/sites-available/wsgi-keystone.conf
Listen 5000
Listen 35357

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>
EOF

ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled

echo "--------------------------"
echo " Restarting apache "
echo "--------------------------"
service apache2 restart && sleep 3

rm -f /var/lib/keystone/keystone.db

export OS_TOKEN=$ADMIN_TOKEN
export OS_URL=http://$IP:35357/v3
export OS_IDENTITY_API_VERSION=3

echo "--------------------------"
echo " Configuring openstack    "
echo "--------------------------"

openstack service create \
  --name keystone --description "OpenStack Identity" identity || fail

openstack endpoint create --region RegionOne \
  identity public http://$IP:5000/v2.0 || fail

openstack endpoint create --region RegionOne \
  identity internal http://$IP:5000/v2.0 || fail

openstack endpoint create --region RegionOne \
  identity admin http://$IP:5000/v2.0 || fail

openstack project create --domain default \
  --description "Admin Project" admin || fail

openstack user create --domain default \
  --password $ADMIN_PASS  admin || fail
sleep 3

openstack role create admin || fail

openstack role add --project admin --user admin admin || fail

openstack project create --domain default \
  --description "Service Project" service || fail

openstack role add --project service --user admin admin || fail

openstack project create --domain default \
  --description "Demo Project" demo || fail

openstack role add --project demo --user admin admin || fail

openstack user create --domain default \
  --password $DEMO_PASS demo || fail

openstack role create user || fail

openstack role add --project demo --user demo user || fail

echo "does keystone need to catch up?"
sleep 3

cat <<EOF >/root/admin-openrc.sh
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=admin
export OS_TENANT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://$IP:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export MYSQL_PASS=$MYSQL_PASS
export NEUTRON_PASS=$NEUTRON_PASS
export NOVA_PASS=$NOVA_PASS
export RABBIT_OS_PASS=$RABBIT_OS_PASS
export HEAT_PASS=$HEAT_PASS
EOF

cat <<EOF >/root/demo-openrc.sh
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=demo
export OS_TENANT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=$DEMO_PASS
export OS_AUTH_URL=http://$IP:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

echo "unset temporary auth mechanism"
unset OS_TOKEN OS_URL

echo "--------------------------"
echo " Verify demo tenant "
echo "--------------------------"

source /root/demo-openrc.sh
openstack token issue || fail

echo "--------------------------"
echo " Verify admin tenant "
echo "--------------------------"

source /root/admin-openrc.sh
openstack token issue || fail

echo "--------------------------"
echo " Installing glance "
echo "--------------------------"

mysqladmin -p$MYSQL_PASS create glance

mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_PASS';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_PASS';"

source /root/admin-openrc.sh

echo "--------------------------"
echo " Creating openstack users "
echo "--------------------------"

openstack user create --domain default --password $GLANCE_PASS glance  || fail
openstack role add --project service --user glance admin || fail

openstack service create --name glance \
  --description "OpenStack Image service" image || fail

openstack endpoint create --region RegionOne \
  image public http://$IP:9292 || fail

openstack endpoint create --region RegionOne \
  image internal http://$IP:9292 || fail

openstack endpoint create --region RegionOne \
  image admin http://$IP:9292 || fail

apt-get install glance python-glanceclient -y

cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.orig

cat <<EOF > /etc/glance/glance-api.conf
[DEFAULT]
notification_driver = noop
[database]
connection = mysql+pymysql://glance:$GLANCE_PASS@$IP/glance
[glance_store]
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
[keystone_authtoken]
auth_uri = http://$IP:5000
auth_url = http://$IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = glance
password = $GLANCE_PASS
[paste_deploy]
flavor = keystone
EOF

cp /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.orig

cat <<EOF > /etc/glance/glance-registry.conf
[DEFAULT]
notification_driver = noop
[database]
connection = mysql+pymysql://glance:$GLANCE_PASS@$IP/glance
[keystone_authtoken]
auth_uri = http://$IP:5000
auth_url = http://$IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = glance
password = $GLANCE_PASS
[paste_deploy]
flavor = keystone
EOF

su -s /bin/sh -c "glance-manage db_sync" glance

service glance-registry restart
service glance-api restart
rm -f /var/lib/glance/glance.sqlite

echo "Let glance start up!"
sleep 3

echo "Verify glance"
wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
glance image-create --name "cirros" \
  --file $(pwd)/cirros-0.3.4-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --visibility public --progress || fail


echo "installing nova"
mysqladmin -p$MYSQL_PASS create nova
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"

openstack user create --domain default --password $NOVA_PASS nova || fail
openstack role add --project service --user nova admin || fail

openstack service create --name nova \
  --description "OpenStack Compute" compute || fail

openstack endpoint create --region RegionOne \
  compute public http://$IP:8774/v2/%\(tenant_id\)s || fail

openstack endpoint create --region RegionOne \
  compute internal http://$IP:8774/v2/%\(tenant_id\)s || fail

openstack endpoint create --region RegionOne \
  compute admin http://$IP:8774/v2/%\(tenant_id\)s || fail

apt-get install nova-api nova-cert nova-conductor \
  nova-consoleauth nova-novncproxy nova-serialproxy nova-scheduler \
  python-novaclient -y

echo "Determine hypervisor type required here"
HTYPE=kvm
if [ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ];
 then
	HTYPE=qemu
fi

cp /etc/nova/nova.conf /etc/nova/nova.conf.orig

cat <<EOF > /etc/nova/nova.conf
[DEFAULT]
#dhcpbridge_flagfile=/etc/nova/nova.conf
#dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
#force_dhcp_release=True
#libvirt_use_virtio_for_bridges=True
verbose=True
#ec2_private_dns_show_ip=True
#api_paste_config=/etc/nova/api-paste.ini
rpc_backend = rabbit
auth_strategy = keystone
my_ip = $IP
metadata_workers = 2
osapi_workers = 2
osapi_compute_workers = 2
#ec2_workers = 2
network_api_class = nova.network.neutronv2.api.API
security_group_api = neutron
linuxnet_interface_driver = nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver
enabled_apis=osapi_compute,metadata
[conductor]
workers = 2
[database]
connection = mysql+pymysql://nova:$NOVA_PASS@$IP/nova
[oslo_messaging_rabbit]
rabbit_host = $IP
rabbit_userid = openstack
rabbit_password = $RABBIT_OS_PASS
[keystone_authtoken]
auth_uri = http://$IP:5000
auth_url = http://$IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = nova
password = $NOVA_PASS
[vnc]
enabled = True
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = $IP
novncproxy_base_url = http://$MGMT_IP:6080/vnc_auto.html
[serial_console]
enabled = True
base_url = ws://$MGMT_IP:6083/
listen = $IP
proxyclient_address = $IP
[glance]
host = $IP
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[libvirt]
virt_type = $HTYPE
[neutron]
url = http://$IP:9696
auth_url = http://$IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASS
service_metadata_proxy = True
metadata_proxy_shared_secret = wistar
EOF

su -s /bin/sh -c "nova-manage db sync" nova

service nova-api restart
service nova-cert restart
service nova-consoleauth restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart

rm -f /var/lib/nova/nova.sqlite

apt-get install nova-compute sysfsutils -y

echo "starting nova-compute"
service nova-compute restart

apt-get install neutron-server neutron-plugin-ml2 \
  neutron-plugin-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent \
  neutron-metadata-agent python-neutronclient -y

#apt-get install neutron-server neutron-plugin-ml2 \
#  neutron-plugin-linuxbridge-agent neutron-dhcp-agent \
#  neutron-metadata-agent python-neutronclient -y

mysqladmin -p$MYSQL_PASS create neutron
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_PASS';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_PASS';"

openstack user create --domain default --password $NEUTRON_PASS neutron || fail
openstack role add --project service --user neutron admin || fail

openstack service create --name neutron \
  --description "OpenStack Networking" network || fail

openstack endpoint create --region RegionOne \
  network public http://$IP:9696 || fail

openstack endpoint create --region RegionOne \
  network internal http://$IP:9696 || fail

openstack endpoint create --region RegionOne \
  network admin http://$IP:9696 || fail

cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig

cat <<EOF > /etc/neutron/neutron.conf
[DEFAULT]
auth_strategy = keystone
rpc_backend = rabbit
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = True
api_workers = 2

notify_nova_on_port_status_changes = True
notify_nova_on_port_data_changes = True
nova_url = http://$IP:8774/v2
[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf
[oslo_concurrency]
lock_path = /var/lib/neutron/lock
[nova]
auth_url = http://$IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = RegionOne
project_name = service
username = nova
password = $NOVA_PASS

[keystone_authtoken]
auth_uri = http://$IP:5000
auth_url = http://$IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $NEUTRON_PASS 
[database]
connection = mysql+pymysql://neutron:$NEUTRON_PASS@$IP/neutron

[oslo_messaging_rabbit]
rabbit_host=$IP
rabbit_port=5672
rabbit_userid=openstack
rabbit_password=$RABBIT_OS_PASS
EOF

cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig

cat <<EOF > /etc/neutron/plugins/ml2/ml2_conf.ini
[ml2]
type_drivers = flat,vlan,vxlan
mechanism_drivers = linuxbridge, l2population
tenant_network_types = vxlan
extension_drivers = port_security
[ml2_type_flat]
flat_networks = public
[ml2_type_vxlan]
vni_ranges = 1:1000
[securitygroup]
enable_ipset = True
EOF

cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.orig

cat <<EOF >/etc/neutron/plugins/ml2/linuxbridge_agent.ini
[linux_bridge]
physical_interface_mappings = public:$EXT_INTERFACE
[vxlan]
enable_vxlan = True
local_ip = $IP
# required to be false in Liberty to ensure vxlan interfaces to do not proxy arp
l2_population = False
[agent]
prevent_arp_spoofing = False
[securitygroup]
enable_security_group = False
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
EOF

cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.orig

cat <<EOF >/etc/neutron/l3_agent.ini
[DEFAULT]
interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver
external_network_bridge =
verbose = True
EOF

cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.orig

cat <<EOF > /etc/neutron/metadata_agent.ini
[DEFAULT]
auth_uri = http://$IP:5000
auth_url = http://$IP:35357
auth_region = RegionOne
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $NEUTRON_PASS
nova_metadata_ip = $IP
metadata_proxy_shared_secret = wistar
EOF

cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.orig

cat <<EOF > /etc/neutron/dhcp_agent.ini
[DEFAULT]
interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = True
verbose = True
dnsmasq_config_file = /etc/neutron/dnsmasq-neutron.conf
EOF

cat <<EOF > /etc/neutron/dnsmasq-neutron.conf
dhcp-option-force=26,1450
EOF

su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

service nova-api restart
service neutron-server restart
service neutron-plugin-linuxbridge-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart

rm -f /var/lib/neutron/neutron.sqlite

echo "--------------------------"
echo " Installing Horizon Dashboard "
echo "--------------------------"

apt-get install openstack-dashboard -y

sed -i.default-role.bkup -e 's/OPENSTACK_KEYSTONE_DEFAULT_ROLE = "_member_"/OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"/' /etc/openstack-dashboard/local_settings.py
sed -i.multi-domain.bkup -e 's/#OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = False/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True/' /etc/openstack-dashboard/local_settings.py

cat <<EOF >> /etc/openstack-dashboard/local_settings.py
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "volume": 2,
}
EOF

echo "--------------------------"
echo " Reloading apache "
echo "--------------------------"
service apache2 restart && sleep 3

echo "--------------------------"
echo " Installing HEAT "
echo "--------------------------"

mysqladmin -p$MYSQL_PASS create heat
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost' IDENTIFIED BY '$HEAT_PASS';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%' IDENTIFIED BY '$HEAT_PASS';"

openstack user create --domain default --password $HEAT_PASS heat || fail
openstack role add --project service --user heat admin || fail

openstack service create --name heat \
  --description "Orchestration" orchestration || fail

openstack service create --name heat-cfn \
  --description "Orchestration"  cloudformation || fail

openstack endpoint create --region RegionOne \
  orchestration public http://$IP:8004/v1/%\(tenant_id\)s || fail

openstack endpoint create --region RegionOne \
  orchestration internal http://$IP:8004/v1/%\(tenant_id\)s || fail

openstack endpoint create --region RegionOne \
  orchestration admin http://$IP:8004/v1/%\(tenant_id\)s || fail

openstack endpoint create --region RegionOne \
  cloudformation public http://$IP:8000/v1 || fail

openstack endpoint create --region RegionOne \
  cloudformation internal http://$IP:8000/v1 || fail

openstack endpoint create --region RegionOne \
  cloudformation admin http://$IP:8000/v1 || fail

openstack domain create --description "Stack projects and users" heat || fail
openstack user create --domain heat --password $HEAT_PASS heat_domain_admin || fail
openstack role add --domain heat --user heat_domain_admin admin || fail

openstack role create heat_stack_owner || fail
openstack role add --project demo --user demo heat_stack_owner || fail

openstack role create heat_stack_user || fail

apt-get install heat-api heat-api-cfn heat-engine \
  python-heatclient -y

cp /etc/heat/heat.conf /etc/heat/heat.conf.orig
cat <<EOF >/etc/heat/heat.conf
[DEFAULT]
rpc_backend = rabbit
heat_metadata_server_url = http://$IP:8000
heat_waitcondition_server_url = http://$IP:8000/v1/waitcondition
stack_domain_admin = heat_domain_admin
stack_domain_admin_password = $HEAT_PASS
stack_user_domain_name = heat
[oslo_messaging_rabbit]
rabbit_host = $IP
rabbit_userid = openstack
rabbit_password = $RABBIT_OS_PASS
[database]
connection = mysql+pymysql://heat:$HEAT_PASS@$IP/heat
[keystone_authtoken]
auth_uri = http://$IP:5000
auth_url = http://$IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = heat
password = $HEAT_PASS

[trustee]
auth_uri = http://$IP:5000
auth_url = http://$IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = heat
password = $HEAT_PASS

[clients_keystone]
auth_uri = http://$IP:5000

[ec2authtoken]
auth_uri = http://$IP:5000
EOF

su -s /bin/sh -c "heat-manage db_sync" heat
service heat-api restart
service heat-api-cfn restart
service heat-engine restart
rm -f /var/lib/heat/heat.sqlite

echo "Creating provider flat network"
neutron net-create public-br-$EXT_INTERFACE --shared --provider:network_type flat --provider:physical_network public --router:external True
neutron subnet-create --ip-version 4 public-br-$EXT_INTERFACE $NET_CIDR --allocation-pool start=$NET_START,end=$NET_END --dns_nameservers list=true 8.8.4.4 8.8.8.8

sleep 1
nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
sleep 1
nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
echo "we're done here"
