#!/bin/bash
# nembery@gmail.com 11-17-15

if [ x$2x == xx ];
 then
  echo "usage: install_openstack_compute.sh controller_address local_address"
  exit 1
fi

CONTROLLER_IP=$1
COMPUTE_IP=$2
echo "Using $CONTROLLER_IP for openstack controller"
echo "Using $COMPUTE_IP for communication to openstack controller"

function fail {
	echo "welp!"
    echo " :-( "
	exit 1
}

# copy all output to a logfile
exec > >(tee -i /var/log/openstack_install.log)
exec 2>&1

echo "--------------------------------"
echo " Getting env from controller"
echo "--------------------------------"

scp root@$CONTROLLER_IP:/root/admin-openrc.sh /root/admin-openrc.sh || fail
source /root/admin-openrc.sh || fail

echo "--------------------------------"
echo " Syncing already downloaded packages "
echo " This assumes controller has been recently updated "
echo "--------------------------------"

rsync -avz root@$CONTROLLER_IP:/var/cache/apt/archives/ /var/cache/apt/archives/ || fail

echo "--------------------------------"
echo " add cloud-archive:liberty      "
echo " and dist-upgrade               "
echo "--------------------------------"
apt-get update 
apt-get install software-properties-common -y || fail
add-apt-repository cloud-archive:liberty -y || fail
apt-get update && apt-get dist-upgrade -y || fail

echo "--------------------------------"
echo " install python-openstackclient "
echo "--------------------------------"

apt-get install python-openstackclient -y

echo "--------------------------------"
echo " Installing Nova                "
echo "--------------------------------"

apt-get install nova-compute sysfsutils ntp -y || fail

echo "--------------------------------"
echo " Determine hypervisor required here "
echo "--------------------------------"

HTYPE=kvm
if [ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ];
 then
    HTYPE=qemu
fi

echo "--------------------------------"
echo " Configuring Nova               "
echo "--------------------------------"

cp /etc/nova/nova.conf /etc/nova/nova.conf.orig

cat <<EOF > /etc/nova/nova.conf
[DEFAULT]
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
force_dhcp_release=True
libvirt_use_virtio_for_bridges=True
verbose=True
ec2_private_dns_show_ip=True
api_paste_config=/etc/nova/api-paste.ini
enabled_apis=ec2,osapi_compute,metadata
rpc_backend = rabbit
auth_strategy = keystone
my_ip = $COMPUTE_IP
network_api_class = nova.network.neutronv2.api.API
security_group_api = neutron
linuxnet_interface_driver = nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver
verbose = True

[oslo_messaging_rabbit]
rabbit_host = $CONTROLLER_IP
rabbit_userid = openstack
rabbit_password = $RABBIT_OS_PASS

[keystone_authtoken]
auth_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = nova
password = $NOVA_PASS

[vnc]
enabled = True
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = $COMPUTE_IP
novncproxy_base_url = http://$CONTROLLER_IP:6080/vnc_auto.html

[serial_console]
enabled = True
base_url = ws://$CONTROLLER_IP:6083/
listen = $COMPUTE_IP
proxyclient_address = $COMPUTE_IP

[glance]
host = $CONTROLLER_IP

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[libvirt]
virt_type = qemu

[neutron]
url = http://$CONTROLLER_IP:9696
auth_url = http://$CONTROLLER_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASS
EOF

echo "--------------------------------"
echo " Starting nova-compute "
echo "--------------------------------"

service nova-compute restart || fail

echo "--------------------------------"
echo " Installing neutron "
echo "--------------------------------"

apt-get install neutron-plugin-linuxbridge-agent conntrack -y || fail

cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig

cat <<EOF > /etc/neutron/neutron.conf
[DEFAULT]
verbose = True
core_plugin = ml2
auth_strategy = keystone
rpc_backend = rabbit
[matchmaker_redis]
[matchmaker_ring]
[quotas]
[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf
[keystone_authtoken]
auth_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $NEUTRON_PASS
[database]
connection = sqlite:////var/lib/neutron/neutron.sqlite
[nova]
[oslo_concurrency]
lock_path = /var/lib/neutron/lock
[oslo_policy]
[oslo_messaging_amqp]
[oslo_messaging_qpid]
[oslo_messaging_rabbit]
rabbit_host = $CONTROLLER_IP
rabbit_userid = openstack
rabbit_password = $RABBIT_OS_PASS
EOF

cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.orig

cat <<EOF >/etc/neutron/plugins/ml2/linuxbridge_agent.ini
[linux_bridge]
physical_interface_mappings = public:eth0
[vxlan]
enable_vxlan = True
vxlan_group = 224.0.0.1
local_ip = $COMPUTE_IP
l2_population = True
[agent]
prevent_arp_spoofing = True
[securitygroup]
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
enable_security_group = True
EOF

echo "--------------------------------"
echo " Restarting Services  "
echo "--------------------------------"

service nova-compute restart || fail
service neutron-plugin-linuxbridge-agent restart || fail

echo "--------------------------------"
echo " All done "
echo " :-) "
echo " "
echo "--------------------------------"
