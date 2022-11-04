#!/bin/bash

# Execute script with flag UPDATE to update the host: ./dappnode_install_pre.sh UPDATE

DAPPNODE_DIR="/usr/src/dappnode"
LOGS_DIR="$DAPPNODE_DIR/logs"
DOCKER_PKG="docker-ce_20.10.6~3-0~debian-bullseye_amd64.deb"
DOCKER_CLI_PKG="docker-ce-cli_20.10.6~3-0~debian-bullseye_amd64.deb"
CONTAINERD_PKG="containerd.io_1.4.4-1_amd64.deb"
DOCKER_REPO="https://download.docker.com/linux/debian/dists/bullseye/pool/stable/amd64"
DOCKER_PATH="${DAPPNODE_DIR}/bin/docker/${DOCKER_PKG}"
DOCKER_CLI_PATH="${DAPPNODE_DIR}/bin/docker/${DOCKER_CLI_PKG}"
CONTAINERD_PATH="${DAPPNODE_DIR}/bin/docker/${CONTAINERD_PKG}"
DCMP_PATH="/usr/local/bin/docker-compose"
DOCKER_URL="${DOCKER_REPO}/${DOCKER_PKG}"
DOCKER_CLI_URL="${DOCKER_REPO}/${DOCKER_CLI_PKG}"
CONTAINERD_URL="${DOCKER_REPO}/${CONTAINERD_PKG}"
DCMP_URL="https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-linux-x86_64"
WGET="wget -q --show-progress --progress=bar:force"
LINUX_FIRMWARE_URL="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/linux-firmware-20221012.tar.gz"

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

# DOCKER INSTALLATION
install_docker() {
    # STEP 0: Detect if it's a Debian 9 (stretch) or Debian 10 (Buster) installation
    # ----------------------------------------
    if [ -f "/etc/os-release" ] && grep -q "buster" "/etc/os-release"; then
        DOCKER_PKG="docker-ce_20.10.2~3-0~debian-buster_amd64.deb"
        DOCKER_CLI_PKG="docker-ce-cli_20.10.2~3-0~debian-buster_amd64.deb"
        CONTAINERD_PKG="containerd.io_1.4.3-1_amd64.deb"
        DOCKER_REPO="https://download.docker.com/linux/debian/dists/buster/pool/stable/amd64"
        DOCKER_PATH="${DAPPNODE_DIR}/bin/docker/${DOCKER_PKG}"
        DOCKER_CLI_PATH="${DAPPNODE_DIR}/bin/docker/${DOCKER_CLI_PKG}"
        CONTAINERD_PATH="${DAPPNODE_DIR}/bin/docker/${CONTAINERD_PKG}"
        DOCKER_URL="${DOCKER_REPO}/${DOCKER_PKG}"
        DOCKER_CLI_URL="${DOCKER_REPO}/${DOCKER_CLI_PKG}"
        CONTAINERD_URL="${DOCKER_REPO}/${CONTAINERD_PKG}"
    elif [ -f "/etc/os-release" ] && grep -q "stretch" "/etc/os-release"; then
        DOCKER_PKG="docker-ce_19.03.8~3-0~debian-stretch_amd64.deb"
        DOCKER_CLI_PKG="docker-ce-cli_19.03.8~3-0~debian-stretch_amd64.deb"
        CONTAINERD_PKG="containerd.io_1.2.6-3_amd64.deb"
        DOCKER_REPO="https://download.docker.com/linux/debian/dists/stretch/pool/stable/amd64"
        DOCKER_PATH="${DAPPNODE_DIR}/bin/docker/${DOCKER_PKG}"
        DOCKER_CLI_PATH="${DAPPNODE_DIR}/bin/docker/${DOCKER_CLI_PKG}"
        CONTAINERD_PATH="${DAPPNODE_DIR}/bin/docker/${CONTAINERD_PKG}"
        DOCKER_URL="${DOCKER_REPO}/${DOCKER_PKG}"
        DOCKER_CLI_URL="${DOCKER_REPO}/${DOCKER_CLI_PKG}"
        CONTAINERD_URL="${DOCKER_REPO}/${CONTAINERD_PKG}"
    fi

    # STEP 1: Download files
    # ----------------------------------------
    [ -f $DOCKER_PATH ] || $WGET -O $DOCKER_PATH $DOCKER_URL
    [ -f $DOCKER_CLI_PATH ] || $WGET -O $DOCKER_CLI_PATH $DOCKER_CLI_URL
    [ -f $CONTAINERD_PATH ] || $WGET -O $CONTAINERD_PATH $CONTAINERD_URL

    # STEP 2: Install packages
    # ----------------------------------------
    dpkg -i $CONTAINERD_PATH 2>&1 | tee -a $LOG_FILE
    dpkg -i $DOCKER_CLI_PATH 2>&1 | tee -a $LOG_FILE
    dpkg -i $DOCKER_PATH 2>&1 | tee -a $LOG_FILE

    # Ensure xz is installed
    [ -f "/usr/bin/xz" ] || (apt-get update -y && apt-get install -y xz-utils)

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
    # STEP 0: Declare paths and directories
    # ----------------------------------------

    # Ensure paths exist
    mkdir -p "$(dirname "$DCMP_PATH")" 2>&1 | tee -a $LOG_FILE

    # STEP 1: Download files
    # ----------------------------------------

    [ -f $DCMP_PATH ] || $WGET -O $DCMP_PATH $DCMP_URL
    # Give permissions
    chmod +x $DCMP_PATH 2>&1 | tee -a $LOG_FILE

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

# WIFI FIRMWARE INSTALLATION (For intel NUC 12)
install_wifi_firmware() {
    # STEP 0: Declare paths and directories
    # ----------------------------------------
    TMP_FIRMWARE_DIR="/tmp/wifi-firmware"

    mkdir -p $TMP_FIRMWARE_DIR

    # STEP 1: Download files
    $WGET -O $TMP_FIRMWARE_DIR/linux-firmware.tar.gz $LINUX_FIRMWARE_URL

    # STEP 2: Install packages
    tar -xvf $TMP_FIRMWARE_DIR/linux-firmware.tar.gz -C $TMP_FIRMWARE_DIR
    cp $TMP_FIRMWARE_DIR/linux-firmware*/iwlwifi-* /lib/firmware/
    cp $TMP_FIRMWARE_DIR/linux-firmware*/intel/ibt-* /lib/firmware/intel/

    #Check if the firmware was installed
    if [ -f "/lib/firmware/iwlwifi-ty-a0-gf-a0-73.ucode" ]; then
        echo -e "\e[32m \n\n Verified wifi firmware installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n ERROR: wifi firmware is not installed \n\n Please re-install it \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
        exit 1
    fi

    # STEP 3: Clean up
    rm -rf $TMP_FIRMWARE_DIR
}

# ADD BACKPORTS SOURCE
add_backports_source(){
    echo -e "deb http://deb.debian.org/debian bullseye-backports main contrib non-free" > /etc/apt/sources.list.d/bullseye-backports.list
    echo -e "deb-src http://deb.debian.org/debian bullseye-backports main contrib non-free" >> /etc/apt/sources.list.d/bullseye-backports.list
}

# ADDITIONAL DRIVERS VIA BACKPORTS (For intel NUC 12)
install_linux_image_via_backports() {

    if  find /etc/apt/ -name "*.list" -print0  | xargs --null cat | grep -q "bullseye-backports" ; then
        echo -e "\e[32m \n\n bullseye-backports source is already added. \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        add_backports_source | tee -a $LOG_FILE
    fi

    apt update -y
    apt -t bullseye-backports install -y linux-image-amd64
}

# WIREGUARD INSTALLATION 
install_wireguard_dkms() {
    apt-get update -y
    if [ -f "/etc/os-release" ] && grep -q "buster" "/etc/os-release"; then
        echo "deb http://deb.debian.org/debian/ buster-backports main" > /etc/apt/sources.list.d/buster-backports.list
        printf 'Package: *\nPin: release a=buster-backports\nPin-Priority: 90\n' > /etc/apt/preferences.d/limit-backports
    fi

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
mkdir -p "$(dirname "$DOCKER_PATH")"

touch $LOG_FILE

# Only update && upgrade host if needed
if [ "$1" == "UPDATE" ]; then
    echo -e "\e[32m \n\n Updating && upgrading host \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    host_update 2>&1 | tee -a $LOG_FILE
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

# Only install wifi firmware if it does not detect the wifi card (Intel NUC 12)
if [[ $(dmidecode | grep "Product Name" | head -1) == *"NUC12"* ]] && [[ -z $(iw dev) ]]; then
    echo -e "\e[32m \n\n Installing wifi firmware \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    install_wifi_firmware 2>&1 | tee -a $LOG_FILE
    install_linux_image_via_backports 2>&1 | tee -a $LOG_FILE
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