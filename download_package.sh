#!/bin/sh
# this will download all the packages 
# useful to download them and snapshot a VM before continueing.

export DEBIAN_FRONTEND=noninteractive

echo "-------------------------------------"
echo "-   Installing packages first       -"
echo "-------------------------------------"

apt-get install -d ntp curl openssl python-keyring -y 
apt-get install -d mariadb-server python-pymysql -y 
apt-get install -d mongodb-server mongodb-clients python-pymongo -y
apt-get install -d rabbitmq-server -y
apt-get install -d keystone apache2 libapache2-mod-wsgi memcached python-memcache -y
apt-get install -d glance python-glanceclient -y
apt-get install -d nova-api nova-cert nova-conductor \
  nova-consoleauth nova-novncproxy nova-scheduler \
  python-novaclient -y
apt-get install -d nova-compute sysfsutils -y
apt-get install -d neutron-server neutron-plugin-ml2 \
  neutron-plugin-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent \
  neutron-metadata-agent python-neutronclient -y
apt-get install -d openstack-dashboard -y
apt-get install -d heat-api heat-api-cfn heat-engine \
  python-heatclient -y

echo "-------------------------------------"
echo "-      Safe to snapshot now!        -"
echo "-------------------------------------"

