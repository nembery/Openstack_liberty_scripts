# openstack_liberty_scripts
Very simple set of scripts to install openstack liberty on ubuntu 14.04. This script automates the official Openstack liberty installation guide found here: http://docs.openstack.org/liberty/install-guide-ubuntu/. 

 Pre-reqs:

 Fresh install of ubuntu 14.04

 All openstack services are installed on a single control node.

 This script assumes a single NIC is present in the control node. 


 Run the following commands before running this script:

 apt-get install software-properties-common

 add-apt-repository cloud-archive:liberty

 apt-get update && apt-get dist-upgrade

 apt-get install python-openstackclient
 
 snapshot as necessary if installing in virtual env

 I use this to install a very generic version of openstack liberty on a fresh ubuntu instance. 

 *** There are a few modifications made to the default options to allow arbitrary IP addresses on ports, enable serial port proxy, disable proxy arp, disable l2_population, among others. These have been commented in the scripts as necessary.

