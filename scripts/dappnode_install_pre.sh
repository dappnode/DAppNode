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
    apt-get remove -y docker docker-engine docker.io containerd runc | tee -a $LOG_FILE
    apt-get install -y ca-certificates curl gnupg lsb-release | tee -a $LOG_FILE
    mkdir -p /etc/apt/keyrings && chmod -R 0755 /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${lsb_dist}/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$lsb_dist $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
}

# DOCKER INSTALLATION
install_docker() {
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io | tee -a $LOG_FILE

    # Ensure xz is installed
    [ -f "/usr/bin/xz" ] || (apt-get install -y xz-utils)

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

# DOCKER-COMPOSE FOR LEGACY SCRIPTS, SHOULD BE REMOVED EVENTUALLY
alias_docker_compose() {
    cat >/usr/local/bin/docker-compose <<EOL
#!/bin/bash
docker compose "\$@"
EOL
    chmod +x /usr/local/bin/docker-compose
}

# WIREGUARD INSTALLATION
install_wireguard_dkms() {
    apt-get update -y

    apt-get install wireguard-dkms -y | tee -a $LOG_FILE

    if modprobe wireguard >/dev/null 2>&1; then
        echo -e "\e[32m \n\n Verified wiregurd-dkms installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: wireguard kernel module is not installed, Wireguard DAppNode package might not work! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# LSOF INSTALLATION: used to scan host port 80 in use, https package installation will deppend on it
install_lsof() {
    apt-get update -y
    apt-get install lsof -y | tee -a $LOG_FILE
    if lsof -v >/dev/null 2>&1; then
        echo -e "\e[32m \n\n Verified lsof installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: lsof not installed, HTTPS DAppNode package might not be installed! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# IPTABLES INSTALLATION: mandatory for docker, on bullseye is not installed by default
install_iptables() {
    apt-get update -y
    apt-get install iptables -y | tee -a $LOG_FILE
    if iptables -v >/dev/null 2>&1; then
        echo -e "\e[32m \n\n Verified iptables installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: iptables not installed, Docker may not work! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# UNATTENDED UPGRADES INSTALLATION: for upgrading system automatically
install_unattendedupgrades() {
    apt-get update -y
    apt-get install unattended-upgrades -y | tee -a $LOG_FILE
    if  unattended-upgrades -h >/dev/null 2>&1 ; then
        echo -e "\e[32m \n\n Verified unattended-upgrades installation \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        echo -e "\e[31m \n\n WARNING: unattended-upgrades not installed, upgrades must be done manually! \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    fi
}

# UNATTENDED UPGRADES SETUP: Enable unattended upgrades and set the configuration
setup_unattendedupgrades() {
    # Check and configure unattended-upgrades config file
    unattended_config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    if [ ! -f "$unattended_config_file" ]; then
        echo -e "\e[31m \n\n WARNING: $unattended_config_file should have been created by the unattended-upgrades package \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
        return 1
    fi

    # Enable automatic removal of unused dependencies and disable automatic reboot
    modify_config_file "$unattended_config_file" 'Unattended-Upgrade::Remove-Unused-Dependencies' 'true'
    modify_config_file "$unattended_config_file" 'Unattended-Upgrade::Automatic-Reboot' 'false'

    # Check and configure auto-upgrades config file
    auto_upgrades_file="/etc/apt/apt.conf.d/20auto-upgrades"
    if [ ! -f "$auto_upgrades_file" ]; then
        # Create the file
        echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
        dpkg-reconfigure -f noninteractive unattended-upgrades

        # Check if the file was created
        if [ ! -f "$auto_upgrades_file" ]; then
            echo -e "\e[31m \n\n WARNING: $auto_upgrades_file could not be created \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
            return 1
        fi
    fi

    # Enable automatic updates and unattended-upgrades (file should exist now)
    modify_config_file "$auto_upgrades_file" 'APT::Periodic::Update-Package-Lists' '1'
    modify_config_file "$auto_upgrades_file" 'APT::Periodic::Unattended-Upgrade' '1'

    echo -e "\e[32m \n\n Verified unattended-upgrades installation and setup. \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
}

# UNATTENDED UPGRADES SETUP: Auxiliary function to modify a setting in a config file
modify_config_file() {
    local config_file="$1"
    local config_setting_key="$2"
    local config_setting_value="$3"
    # Remove any appearances of the key from the file
    sed -i "/^$config_setting_key .*/d" "$config_file"
    # Add the updated setting
    echo "$config_setting_key \"$config_setting_value\";" >> "$config_file"
}


# HOST UPDATE
host_update() {
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

if find /etc/apt/ -name "*.list" -print0 | xargs --null cat | grep -q "https://download.docker.com/linux/$lsb_dist"; then
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

# Only install wireguard-dkms if needed
if modprobe wireguard >/dev/null 2>&1; then
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

if [[ $SKIP_UNATTENDED_UPGRADES != "true"  ]]; then 
    # Only install unatended upgrades if needed
    if unattended-upgrades -h  >/dev/null 2>&1; then
        echo -e "\e[32m \n\n unattended-upgrades is already installed \n\n \e[0m" 2>&1 | tee -a $LOG_FILE
    else
        install_unattendedupgrades 2>&1 | tee -a $LOG_FILE
    fi
fi

#Check connectivity
{ [ -f /etc/network/interfaces ] && grep "iface en.* inet dhcp" /etc/network/interfaces &>/dev/null; } || {
    echo "Interfaces not found"
    exit 1
}

## Add missing interfaces
if [ -f /usr/src/dappnode/hotplug ]; then
    # shellcheck disable=SC2013
    for IFACE in $(grep "en.*" /usr/src/dappnode/hotplug); do
        # shellcheck disable=SC2143
        if [[ $(grep -L "$IFACE" /etc/network/interfaces) ]]; then
            {
                echo "# $IFACE"
                echo "allow-hotplug $IFACE"
                echo "iface $IFACE inet dhcp"
            } >>/etc/network/interfaces
        fi
    done
fi
