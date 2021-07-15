#!/bin/bash

#########################
#dappnode_install_pre.sh#
#########################

# Docker should be uninstalled
# apt-get purge docker-ce docker-ce-cli containerd.io ==> NOT able to uninstall docker on github host

# Create necessary folder
mkdir -p /etc/network/
echo "iface en.x inet dhcp" >> /etc/network/interfaces

##########################
#dappnode_test_install.sh#
##########################

## Not able to do ping inside github host