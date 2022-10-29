#!/bin/bash

# Execute script with flag UPDATE to update the host: ./dappnode_install_pre.sh UPDATE

DAPPNODE_DIR="/usr/src/dappnode"
LOGS_DIR="$DAPPNODE_DIR/logs"
lsb_dist="$(. /etc/os-release && echo "$ID")"


#!ISOBUILD Do not modify, variables above imported for ISO build

detect_installation_type() {
    if [ -f "${DAPPNODE_DIR}/iso_install.log" ]; then
        LOG_FILE="${LOGS_DIR}/iso_install.log"
        rm -f "${DAPPNODE_DIR}/iso_install.log"
        ISO_INSTALLATION=true
    else
        LOG_FILE="${LOGS_DIR}/install.log"
        ISO_INSTALLATION=false
    fi
}


add_docker_repo() {
    apt-get update -y
    apt-get remove -y docker docker-engine docker.io containerd runc  | tee -a $LOG_FILE
    apt-get install -y ca-certificates curl gnupg lsb-release | tee -a $LOG_FILE
    mkdir -p /etc/apt/keyrings && chmod -R 0755 /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${lsb_dist}/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$lsb_dist $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
}

# DOCKER INSTALLATION
install_docker() {
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io | tee -a $LOG_FILE

    # Ensure xz is installed
    [ -f "/usr/bin/xz" ] || ( apt-get install -y xz-utils)

    USER=$(grep 1000 "/etc/passwd" | cut -f 1 -d:)
    [ -z "$USER" ] || usermod -aG docker "$USER"

    # Disable check if ISO installation since it is not possible to check in this way
    if [ "$ISO_INSTALLATION" = "false" ]; then
        # Validate the installation of docker
        if docker -v; then
            echo -e "\e[32m \n\n Verified docker installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
        else
            echo -e "\e[31m \n\n ERROR: docker is not installed \n\n Please re-install it \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
            exit 1
        fi
    fi
}

# DOCKER COMPOSE INSTALLATION
install_docker_compose() {
    apt-get install -y docker-compose | tee -a $LOG_FILE

    # Disable check if ISO installation since it is not possible to check in this way
    if [ "$ISO_INSTALLATION" = "false" ]; then
        # Validate the installation of docker-compose
        if docker-compose -v; then
            echo -e "\e[32m \n\n Verified docker-compose installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
        else
            echo -e "\e[31m \n\n ERROR: docker-compose is not installed \n\n Please re-install it \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
            exit 1
        fi
    fi
}

# WIREGUARD INSTALLATION 
install_wireguard_dkms() {
    apt-get update -y

    apt-get install wireguard-dkms -y | tee -a $LOG_FILE

    if  modprobe wireguard >/dev/null 2>&1 ; then
        echo -e "\e[32m \n\n Verified wiregurd-dkms installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: wireguard kernel module is not installed, Wireguard DAppNode package might not work! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# LSOF INSTALLATION: used to scan host port 80 in use, https package installation will deppend on it  
install_lsof() {
    apt-get update -y
    apt-get install lsof -y | tee -a $LOG_FILE
    if  lsof -v >/dev/null 2>&1 ; then
        echo -e "\e[32m \n\n Verified lsof installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: lsof not installed, HTTPS DAppNode package might not be installed! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# IPTABLES INSTALLATION: mandatory for docker, on bullseye is not installed by default
install_iptables () {
    apt-get update -y
    apt-get install iptables -y | tee -a $LOG_FILE
    if  iptables -v >/dev/null 2>&1 ; then
        echo -e "\e[32m \n\n Verified iptables installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: iptables not installed, Docker may not work! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# HOST UPDATE
host_update () {
    apt-get update 2>&1 | tee -a $LOG_FILE
    apt-get -y upgrade 2>&1 | tee -a $LOG_FILE
}

##############################################
####             SCRIPT START             ####
##############################################

detect_installation_type

# Ensure paths exist
mkdir -p $DAPPNODE_DIR
mkdir -p $LOGS_DIR

touch $LOG_FILE

# Only update && upgrade host if needed
if [ "$1" == "UPDATE" ]; then
    echo -e "\e[32m \n\n Updating && upgrading host \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    host_update 2>&1 | tee -a $LOG_FILE
fi


if  find /etc/apt/ -name "*.list" -print0  | xargs --null cat | grep -q "https://download.docker.com/linux/$lsb_dist" ; then
    echo -e "\e[32m \n\n docker repo is already added \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
else
    add_docker_repo | tee -a $LOG_FILE
fi

# Only install docker if needed
if docker -v >/dev/null 2>&1; then
    echo -e "\e[32m \n\n docker is already installed \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
else
    install_docker 2>&1 | tee -a $LOG_FILE
fi

# Only install docker-compose if needed
if docker-compose -v >/dev/null 2>&1; then
    echo -e "\e[32m \n\n docker-compose is already installed \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
else
    install_docker_compose 2>&1 | tee -a $LOG_FILE
fi

# Only install wireguard-dkms if needed
if modprobe wireguard >/dev/null 2>&1 ; then
    echo -e "\e[32m \n\n wireguard-dkms is already installed \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
else
    install_wireguard_dkms 2>&1 | tee -a $LOG_FILE
fi

# Only install lsof if needed
if lsof -v >/dev/null 2>&1; then
    echo -e "\e[32m \n\n lsof is already installed \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
else
    install_lsof 2>&1 | tee -a $LOG_FILE
fi

#Check connectivity
{ [ -f /etc/network/interfaces ] && grep "iface en.* inet dhcp" /etc/network/interfaces &>/dev/null; } || { echo "Interfaces not found"; exit 1; }

## Add missing interfaces
if [ -f /usr/src/dappnode/hotplug ]; then
    # shellcheck disable=SC2013
    for IFACE in $(grep "en.*" /usr/src/dappnode/hotplug); do
        # shellcheck disable=SC2143
        if [[ $(grep -L "$IFACE" /etc/network/interfaces) ]]; then
            { echo "# $IFACE"; echo "allow-hotplug $IFACE"; echo "iface $IFACE inet dhcp"; } >> /etc/network/interfaces
        fi
    done
fi
