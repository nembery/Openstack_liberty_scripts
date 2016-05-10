# openstack_liberty_install_generic
Very simple script to install openstack liberty on ubuntu 14.04. This script automates the official Openstack liberty installation guide found here: http://docs.openstack.org/liberty/install-guide-ubuntu/. 

 Pre-reqs:
 ubuntu 14.04

 Run the following commands before running this script:
 apt-get install software-properties-common
 add-apt-repository cloud-archive:liberty
 apt-get update && apt-get dist-upgrade
 apt-get install python-openstackclient
 
 snapshot as necessary if installing in virtual env

I use this to install a very generic version of openstack liberty on a fresh ubuntu instance. 

