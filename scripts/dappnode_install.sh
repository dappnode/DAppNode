#!/bin/bash

# This installer is written for bash. It's safe to *run it from zsh* (it will execute via bash
# thanks to the shebang), but users sometimes invoke it as `zsh ./script.sh` or `source ./script.sh`.
# - If sourced, bail out (sourcing would pollute the current shell and can break it).
# - If invoked by a non-bash shell, re-exec with bash before hitting bash-specific builtins.
if (return 0 2>/dev/null); then
    echo "This script must be executed, not sourced. Run: bash $0"
    return 1
fi

if [ -z "${BASH_VERSION:-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -eo pipefail

# Enable alias expansion in non-interactive bash scripts.
# Required so commands like `dappnode_wireguard` (defined as aliases in `.dappnode_profile`) work.
shopt -s expand_aliases

##################
# OS DETECTION   #
##################
OS_TYPE="$(uname -s)"
IS_MACOS=false
IS_LINUX=false
if [[ "$OS_TYPE" == "Darwin" ]]; then
    IS_MACOS=true
elif [[ "$OS_TYPE" == "Linux" ]]; then
    IS_LINUX=true
else
    echo "Unsupported operating system: $OS_TYPE"
    exit 1
fi

#############
# VARIABLES #
#############
# Dirs - macOS uses $HOME/dappnode, Linux uses /usr/src/dappnode
if $IS_MACOS; then
    DAPPNODE_DIR="$HOME/dappnode"
else
    DAPPNODE_DIR="/usr/src/dappnode"
fi
DAPPNODE_CORE_DIR="${DAPPNODE_DIR}/DNCORE"
LOGS_DIR="$DAPPNODE_DIR/logs"
# Files
CONTENT_HASH_FILE="${DAPPNODE_CORE_DIR}/packages-content-hash.csv"
LOGFILE="${LOGS_DIR}/dappnode_install.log"
DAPPNODE_PROFILE="${DAPPNODE_CORE_DIR}/.dappnode_profile"
# Linux-only paths
if $IS_LINUX; then
    MOTD_FILE="/etc/motd"
    UPDATE_MOTD_DIR="/etc/update-motd.d"
fi
# Get URLs
PROFILE_BRANCH=${PROFILE_BRANCH:-"master"}
IPFS_ENDPOINT=${IPFS_ENDPOINT:-"http://ipfs.io"}
# PROFILE_URL env is used to fetch the core packages versions that will be used to build the release in script install method
PROFILE_URL=${PROFILE_URL:-"https://github.com/dappnode/DAppNode/releases/latest/download/dappnode_profile.sh"}
DAPPNODE_ACCESS_CREDENTIALS="${DAPPNODE_DIR}/scripts/dappnode_access_credentials.sh"
DAPPNODE_ACCESS_CREDENTIALS_URL="https://github.com/dappnode/DAppNode/releases/latest/download/dappnode_access_credentials.sh"
# Other

# Architecture detection (cross-platform)
if $IS_MACOS; then
    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
    # arm64 is already correct for Apple Silicon
else
    ARCH=$(dpkg --print-architecture)
fi

##############################
# Cross-platform Helpers     #
##############################

# Download a file: download_file <destination> <url>
download_file() {
    local dest="$1"
    local url="$2"
    if $IS_MACOS; then
        curl -sL -o "$dest" "$url"
    else
        wget -q --show-progress --progress=bar:force -O "$dest" "$url"
    fi
}

# Download content to stdout: download_stdout <url>
download_stdout() {
    local url="$1"
    if $IS_MACOS; then
        curl -sL "$url"
    else
        wget -q -O- "$url"
    fi
}

# Cross-platform in-place sed (macOS requires '' after -i)
sed_inplace() {
    if $IS_MACOS; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

##############################
# Compose Patching Helpers   #
##############################

# Remove journald logging from compose files (not supported on macOS Docker Desktop)
remove_logging_section() {
    local file="$1"
    sed_inplace '/logging/d;/journald/d' "$file"
}

# Replace Linux paths with macOS paths in compose files
patch_compose_paths() {
    local file="$1"
    sed_inplace "s|/usr/src/dappnode|${DAPPNODE_DIR}|g" "$file"
}

# TODO: remove once profile macos-compatibility published
# Patch .dappnode_profile for macOS compatibility
patch_profile_for_macos() {
    local profile="$1"
    # Replace GNU find -printf with POSIX-compatible -exec printf
    sed_inplace 's/-printf "-f %p "/-exec printf -- "-f %s " {} \\;/' "$profile"
    # Replace hardcoded Linux paths with $HOME-based paths
    sed_inplace 's|/usr/src/dappnode|\$HOME/dappnode|g' "$profile"
}

# Clean if update
if [ "$UPDATE" = true ]; then
    echo "Cleaning for update..."
    rm -rf $LOGFILE
    rm -rf ${DAPPNODE_CORE_DIR}/docker-compose-*.yml
    rm -rf ${DAPPNODE_CORE_DIR}/dappnode_package-*.json
    rm -rf ${DAPPNODE_CORE_DIR}/*.tar.xz
    rm -rf ${DAPPNODE_CORE_DIR}/*.txz
    rm -rf ${DAPPNODE_CORE_DIR}/.dappnode_profile
    rm -rf ${CONTENT_HASH_FILE}
fi

# Create necessary directories
mkdir -p $DAPPNODE_DIR
mkdir -p $DAPPNODE_CORE_DIR
mkdir -p "${DAPPNODE_DIR}/scripts"
mkdir -p "${DAPPNODE_CORE_DIR}/scripts"
mkdir -p "${DAPPNODE_DIR}/config"
mkdir -p $LOGS_DIR

# TEMPORARY: think a way to integrate flags instead of use files to detect installation type
is_iso_install() {
    # ISO installs are Linux-only
    if $IS_MACOS; then
        IS_ISO_INSTALL=false
        return
    fi
    # Check old and new location of iso_install.log
    if [ -f "${DAPPNODE_DIR}/iso_install.log" ] || [ -f "${DAPPNODE_DIR}/logs/iso_install.log" ]; then
        IS_ISO_INSTALL=true
    else
        IS_ISO_INSTALL=false
    fi
}

# Check if port 80 is in use (necessary for HTTPS)
# Returns IS_PORT_USED=true only if port 80 or 443 is used by something OTHER than our HTTPS container
is_port_used() {
    # Check if port 80 or 443 is in use at all
    local port80_used port443_used
    lsof -i -P -n | grep ":80 (LISTEN)" &>/dev/null && port80_used=true || port80_used=false
    lsof -i -P -n | grep ":443 (LISTEN)" &>/dev/null && port443_used=true || port443_used=false

    if [ "$port80_used" = false ] && [ "$port443_used" = false ]; then
        IS_PORT_USED=false
        return
    fi

    # If either port is in use, check if it's our HTTPS container
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^DAppNodeCore-https.dnp.dappnode.eth$"; then
        # Port 80 or 443 is used by our HTTPS container, so we consider it "not used" for package determination
        IS_PORT_USED=false
    else
        # Port 80 or 443 is used by something else
        IS_PORT_USED=true
    fi
}

# Determine packages to be installed
determine_packages() {
    is_iso_install
    is_port_used
    if [ "$IS_ISO_INSTALL" == "false" ]; then
        if [ "$IS_PORT_USED" == "true" ]; then
            PKGS=(BIND IPFS VPN WIREGUARD DAPPMANAGER WIFI)
        else
            PKGS=(HTTPS BIND IPFS WIREGUARD DAPPMANAGER WIFI)
        fi
    else
        if [ "$IS_PORT_USED" == "true" ]; then
            PKGS=(BIND IPFS WIREGUARD DAPPMANAGER WIFI)
        else
            PKGS=(HTTPS BIND IPFS WIREGUARD DAPPMANAGER WIFI)
        fi
    fi
    echo -e "\e[32mPackages to be installed: ${PKGS[*]}\e[0m" 2>&1 | tee -a $LOGFILE
}

function valid_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=("$ip")
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 &&
            ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

if [[ -n "$STATIC_IP" ]]; then
    if valid_ip "$STATIC_IP"; then
        echo "$STATIC_IP" >${DAPPNODE_DIR}/config/static_ip
    else
        echo "The static IP provided: ${STATIC_IP} is not valid."
        exit 1
    fi
fi

# Loads profile, if not exists it means it is script install so the versions will be fetched from the latest profile
[ -f "$DAPPNODE_PROFILE" ] || download_file "${DAPPNODE_PROFILE}" "${PROFILE_URL}"

# Patch profile for macOS compatibility (replace GNU-isms and hardcoded Linux paths)
# TODO: remove once profile macos-compatibility published
if $IS_MACOS; then
    patch_profile_for_macos "$DAPPNODE_PROFILE"
fi

# shellcheck disable=SC1090
source "${DAPPNODE_PROFILE}"

# The indirect variable expansion used in ${!ver##*:} allows us to use versions like 'dev:development'
# If such variable with 'dev:'' suffix is used, then the component is built from specified branch or commit.
# you can also specify an IPFS version like /ipfs/QmWg8P2b9JKQ8thAVz49J8SbJbCoi2MwkHnUqMtpzDTtxR:0.2.7, it's important
# to include the exact version also in the IPFS hash format since it's needed to be able to download it
determine_packages
for comp in "${PKGS[@]}"; do
    ver="${comp}_VERSION"
    DOWNLOAD_URL="https://github.com/dappnode/DNP_${comp}/releases/download/v${!ver}"
    if [[ ${!ver} == /ipfs/* ]]; then
        DOWNLOAD_URL="${IPFS_ENDPOINT}/api/v0/cat?arg=${!ver%:*}"
    fi
    comp_lower=$(echo "$comp" | tr '[:upper:]' '[:lower:]')
    eval "${comp}_URL=\"${DOWNLOAD_URL}/${comp_lower}.dnp.dappnode.eth_${!ver##*:}_linux-${ARCH}.txz\""
    eval "${comp}_YML=\"${DOWNLOAD_URL}/docker-compose.yml\""
    eval "${comp}_MANIFEST=\"${DOWNLOAD_URL}/dappnode_package.json\""
    eval "${comp}_YML_FILE=\"${DAPPNODE_CORE_DIR}/docker-compose-${comp_lower}.yml\""
    eval "${comp}_FILE=\"${DAPPNODE_CORE_DIR}/${comp_lower}.dnp.dappnode.eth_${!ver##*:}_linux-${ARCH}.txz\""
    eval "${comp}_MANIFEST_FILE=\"${DAPPNODE_CORE_DIR}/dappnode_package-${comp_lower}.json\""
done

dappnode_core_build() {
    for comp in "${PKGS[@]}"; do
        ver="${comp}_VERSION"
        if [[ ${!ver} == dev:* ]]; then
            if $IS_MACOS; then
                echo "Development builds (dev:*) are not supported on macOS."
                exit 1
            fi
            echo "Cloning & building DNP_${comp}..."
            if ! dpkg -s git >/dev/null 2>&1; then
                apt-get install -y git
            fi
            TMPDIR=$(mktemp -d)
            pushd "$TMPDIR" || {
                echo "Error on pushd"
                exit 1
            }
            git clone -b "${!ver##*:}" https://github.com/dappnode/DNP_"${comp}"
            # Change version in YAML to the custom one
            DOCKER_VER=$(echo "${!ver##*:}" | sed 's/\//_/g')
            sed -i "s~^\(\s*image\s*:\s*\).*~\1${comp,,}.dnp.dappnode.eth:${DOCKER_VER}~" DNP_"${comp}"/docker-compose.yml
            docker compose -f ./DNP_"${comp}"/docker-compose.yml build
            cp ./DNP_"${comp}"/docker-compose.yml "${DAPPNODE_CORE_DIR}"/docker-compose-"${comp,,}".yml
            cp ./DNP_"${comp}"/dappnode_package.json "${DAPPNODE_CORE_DIR}"/dappnode_package-"${comp,,}".json
            rm -r ./DNP_"${comp}"
            popd || {
                echo "Error on popd"
                exit 1
            }
        fi
    done
}

dappnode_core_download() {
    for comp in "${PKGS[@]}"; do
        ver="${comp}_VERSION"
        if [[ ${!ver} != dev:* ]]; then
            local file_var="${comp}_FILE"
            local url_var="${comp}_URL"
            local yml_file_var="${comp}_YML_FILE"
            local yml_var="${comp}_YML"
            local manifest_file_var="${comp}_MANIFEST_FILE"
            local manifest_var="${comp}_MANIFEST"

            # Download DAppNode Core Images if needed
            echo "Downloading ${comp} tar..."
            [ -f "${!file_var}" ] || download_file "${!file_var}" "${!url_var}" || exit 1
            # Download DAppNode Core docker-compose yml files if needed
            echo "Downloading ${comp} yml..."
            [ -f "${!yml_file_var}" ] || download_file "${!yml_file_var}" "${!yml_var}" || exit 1
            # Download DAppNode Core manifest files if needed
            echo "Downloading ${comp} manifest..."
            [ -f "${!manifest_file_var}" ] || download_file "${!manifest_file_var}" "${!manifest_var}" || exit 1

            # macOS: patch compose files for Docker Desktop compatibility
            if $IS_MACOS; then
                remove_logging_section "${!yml_file_var}"
                patch_compose_paths "${!yml_file_var}"
            fi
        fi
    done
}

dappnode_core_load() {
    for comp in "${PKGS[@]}"; do
        ver="${comp}_VERSION"
        if [[ ${!ver} != dev:* ]]; then
            eval "[ ! -z \$(docker images -q ${comp,,}.dnp.dappnode.eth:${!ver##*:}) ] || docker load -i \$${comp}_FILE 2>&1 | tee -a \$LOGFILE"
        fi
    done
}

customMotd() {
    generateMotdText

    if [ -d "${UPDATE_MOTD_DIR}" ]; then
        # Ubuntu configuration
        modifyMotdGeneration
    fi
}

# Debian distros use /etc/motd plain text file
generateMotdText() {
    local welcome_message

    # Check and create the MOTD file if it does not exist
    if [ ! -f "${MOTD_FILE}" ]; then
        touch "${MOTD_FILE}"
    fi

    # Write the ASCII art and welcome message as plain text
    cat <<'EOF' >"${MOTD_FILE}"
  ___                              _     
 |   \ __ _ _ __ _ __ _ _  ___  __| |___ 
 | |) / _` | '_ \ '_ \ ' \/ _ \/ _` / -_)
 |___/\__,_| .__/ .__/_||_\___/\__,_\___|
           |_|  |_|                      
EOF
    welcome_message="\nChoose a way to connect to your DAppNode, then go to \e[1mhttp://my.dappnode\e[0m\n\n\e[1m- Wifi\e[0m\t\tScan and connect to DAppNodeWIFI. Get wifi credentials with \e[32mdappnode_wifi\e[0m\n\n\e[1m- Local Proxy\e[0m\tConnect to the same router as your DAppNode. Then go to \e[1mhttp://dappnode.local\e[0m\n\n\e[1m- Wireguard\e[0m\tDownload Wireguard app on your device. Get your dappnode wireguard credentials with \e[32mdappnode_wireguard\e[0m\n\n\e[1m- Open VPN\e[0m\tDownload OPen VPN app on your device. Get your openVPN creds with \e[32mdappnode_openvpn\e[0m\n\n\nTo see a full list of commands available execute \e[32mdappnode_help\e[0m\n"
    printf "%b" "$welcome_message" >>"${MOTD_FILE}"
}

# Ubuntu distros use /etc/update-motd.d/ to generate the motd
modifyMotdGeneration() {
    disabled_motd_dir="${UPDATE_MOTD_DIR}/disabled"

    mkdir -p "${disabled_motd_dir}"

    # Move all the files in /etc/update-motd.d/ to /etc/update-motd.d/disabled/
    # Except for the files listed in "files_to_keep"
    files_to_keep="00-header 50-landscape-sysinfo 98-reboot-required"
    for file in ${UPDATE_MOTD_DIR}/*; do
        base_file=$(basename "${file}")
        if [ -f "${file}" ] && ! echo "${files_to_keep}" | grep -qw "${base_file}"; then
            mv "${file}" "${disabled_motd_dir}/"
        fi
    done
}

addSwap() {
    # Is swap enabled?
    IS_SWAP=$(swapon --show | wc -l)

    # if not then create it
    if [ "$IS_SWAP" -eq 0 ]; then
        echo -e '\e[32mSwap not found. Adding swapfile.\e[0m'
        #RAM=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        #SWAP=$(($RAM * 2))
        SWAP=8388608
        fallocate -l ${SWAP}k /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap defaults 0 0' >>/etc/fstab
    else
        echo -e '\e[32mSwap found. No changes made.\e[0m'
    fi
}

# Add .dappnode_profile sourcing to the user's default shell configuration
add_profile_to_shell() {
    local user_home
    local shell_configs

    if $IS_MACOS; then
        user_home="$HOME"
        # macOS defaults to zsh
        shell_configs=(".zshrc" ".zprofile")
    else
        # Linux: determine user home from /etc/passwd
        local user_name
        user_name=$(grep 1000 /etc/passwd | cut -f 1 -d:)
        if [ -n "$user_name" ]; then
            user_home="/home/$user_name"
        else
            user_home="/root"
        fi
        shell_configs=(".profile" ".bashrc")
    fi

    for config_file in "${shell_configs[@]}"; do
        local config_path="${user_home}/${config_file}"
        local source_line

        # .profile may be evaluated by /bin/sh (dash on Debian/Ubuntu) where `source` is not valid.
        # Use POSIX '.' there; use `source` elsewhere (bash/zsh).
        if [ "$config_file" = ".profile" ]; then
            source_line="[ -f \"${DAPPNODE_PROFILE}\" ] && . \"${DAPPNODE_PROFILE}\""
        else
            source_line="[ -f \"${DAPPNODE_PROFILE}\" ] && source \"${DAPPNODE_PROFILE}\""
        fi

        # Create config file if it doesn't exist
        [ ! -f "$config_path" ] && touch "$config_path"
        # Add profile sourcing if not already present
        if ! grep -q "${DAPPNODE_PROFILE}" "$config_path"; then
            echo "########          DAPPNODE PROFILE          ########" >> "$config_path"
            echo "$source_line" >> "$config_path"
            echo "" >> "$config_path"
        fi
    done
}

dappnode_core_start() {
    echo -e "\e[32mDAppNode starting...\e[0m" 2>&1 | tee -a $LOGFILE

    # Use DNCORE_YMLS from the profile (populated after re-sourcing post-download)
    docker compose $DNCORE_YMLS up -d 2>&1 | tee -a $LOGFILE
    echo -e "\e[32mDAppNode started\e[0m" 2>&1 | tee -a $LOGFILE

    # Add profile sourcing to user's shell configuration
    add_profile_to_shell

    # Remove return from profile so it can be sourced in login shells
    sed_inplace '/return/d' "$DAPPNODE_PROFILE"

    # Download access_credentials script
    [ -f "$DAPPNODE_ACCESS_CREDENTIALS" ] || download_file "${DAPPNODE_ACCESS_CREDENTIALS}" "${DAPPNODE_ACCESS_CREDENTIALS_URL}"

    # Linux-only: clean up rc.local
    if $IS_LINUX; then
        if [ -f "/etc/rc.local" ] && [ ! -f "${DAPPNODE_DIR}/.firstboot" ]; then
            sed_inplace '/\/usr\/src\/dappnode\/scripts\/dappnode_install.sh/d' /etc/rc.local 2>&1 | tee -a $LOGFILE
        fi
    fi

    # Display help message to the user
    echo -e "Execute \e[32mdappnode_help\e[0m to see a full list with commands available"
}

installExtraDpkg() {
    if [ -d "/usr/src/dappnode/extra_dpkg" ]; then
        dpkg -i /usr/src/dappnode/iso/extra_dpkg/*.deb 2>&1 | tee -a $LOGFILE
    fi
}

grabContentHashes() {
    if [ ! -f "${CONTENT_HASH_FILE}" ]; then
        local content_hash_pkgs=(geth besu nethermind erigon prysm teku lighthouse nimbus lodestar)
        for comp in "${content_hash_pkgs[@]}"; do
            CONTENT_HASH=$(download_stdout "https://github.com/dappnode/DAppNodePackage-${comp}/releases/latest/download/content-hash")
            if [ -z "$CONTENT_HASH" ]; then
                echo "ERROR! Failed to find content hash of ${comp}." 2>&1 | tee -a $LOGFILE
                exit 1
            fi
            echo "${comp}.dnp.dappnode.eth,${CONTENT_HASH}" >>${CONTENT_HASH_FILE}
        done
    fi
}

# /sgx will only be installed on ISO's dappnode not on standalone script
installSgx() {
    if [ -d "/usr/src/dappnode/iso/sgx" ]; then
        # from sgx_linux_x64_driver_2.5.0_2605efa.bin
        /usr/src/dappnode/iso/sgx/sgx_linux_x64_driver.bin 2>&1 | tee -a $LOGFILE
        /usr/src/dappnode/iso/sgx/enable_sgx 2>&1 | tee -a $LOGFILE
    fi
}

# /extra_dpkg will only be installed on ISO's dappnode not on standalone script
installExtraDpkg() {
    if [ -d "/usr/src/dappnode/iso/extra_dpkg" ]; then
        dpkg -i /usr/src/dappnode/extra_dpkg/*.deb 2>&1 | tee -a $LOGFILE
    fi
}

# The main user needs to be added to the docker group to be able to run docker commands without sudo
# Explained in: https://docs.docker.com/engine/install/linux-postinstall/
addUserToDockerGroup() {
    # UID is provided to the first regular user created in the system
    USER=$(grep 1000 "/etc/passwd" | cut -f 1 -d:)

    # If USER is not found, warn the user and return
    if [ -z "$USER" ]; then
        echo -e "\e[33mWARN: Default user not found. Could not add it to the docker group.\e[0m" 2>&1 | tee -a $LOGFILE
        return
    fi

    if groups "$USER" | grep &>/dev/null '\bdocker\b'; then
        echo -e "\e[32mUser $USER is already in the docker group\e[0m" 2>&1 | tee -a $LOGFILE
        return
    fi

    # This step is already done in the dappnode_install_pre.sh script,
    # but it's not working in the Ubuntu ISO because the late-commands in the autoinstall.yaml
    # file are executed before the user is created.
    usermod -aG docker "$USER"
    echo -e "\e[32mUser $USER added to the docker group\e[0m" 2>&1 | tee -a $LOGFILE
}

##############################################
####             SCRIPT START             ####
##############################################

echo -e "\e[32m\n##############################################\e[0m" 2>&1 | tee -a $LOGFILE
echo -e "\e[32m####          DAPPNODE INSTALLER          ####\e[0m" 2>&1 | tee -a $LOGFILE
echo -e "\e[32m##############################################\e[0m" 2>&1 | tee -a $LOGFILE

# --- Linux-only setup steps ---
if $IS_LINUX; then
    echo -e "\e[32mCreating swap memory...\e[0m" 2>&1 | tee -a $LOGFILE
    addSwap

    echo -e "\e[32mCustomizing login...\e[0m" 2>&1 | tee -a $LOGFILE
    customMotd

    echo -e "\e[32mInstalling extra packages...\e[0m" 2>&1 | tee -a $LOGFILE
    installExtraDpkg

    echo -e "\e[32mGrabbing latest content hashes...\e[0m" 2>&1 | tee -a $LOGFILE
    grabContentHashes

    if [ "$ARCH" == "amd64" ]; then
        echo -e "\e[32mInstalling SGX modules...\e[0m" 2>&1 | tee -a $LOGFILE
        installSgx

        echo -e "\e[32mInstalling extra packages...\e[0m" 2>&1 | tee -a $LOGFILE
        installExtraDpkg # TODO: Why is this being called twice?
    fi

    echo -e "\e[32mAdding user to docker group...\e[0m" 2>&1 | tee -a $LOGFILE
    addUserToDockerGroup
fi

# --- Common steps (Linux and macOS) ---
echo -e "\e[32mCreating dncore_network if needed...\e[0m" 2>&1 | tee -a $LOGFILE
docker network create --driver bridge --subnet 172.33.0.0/16 dncore_network 2>&1 | tee -a $LOGFILE || true

echo -e "\e[32mBuilding DAppNode Core if needed...\e[0m" 2>&1 | tee -a $LOGFILE
dappnode_core_build

echo -e "\e[32mDownloading DAppNode Core...\e[0m" 2>&1 | tee -a $LOGFILE
dappnode_core_download

# Re-source profile now that compose files exist, so DNCORE_YMLS is populated
# shellcheck disable=SC1090
source "${DAPPNODE_PROFILE}"

echo -e "\e[32mLoading DAppNode Core...\e[0m" 2>&1 | tee -a $LOGFILE
dappnode_core_load

# --- Start DAppNode ---
if $IS_LINUX; then
    if [ ! -f "${DAPPNODE_DIR}/.firstboot" ]; then
        echo -e "\e[32mDAppNode installed\e[0m" 2>&1 | tee -a $LOGFILE
        dappnode_core_start
    fi

    # Run test in interactive terminal (first boot only)
    if [ -f "${DAPPNODE_DIR}/.firstboot" ]; then
        apt-get update
        apt-get install -y kbd
        openvt -s -w -- sudo -u root "${DAPPNODE_DIR}/scripts/dappnode_test_install.sh"
        exit 0
    fi
fi

if $IS_MACOS; then
    echo -e "\e[32mDAppNode installed\e[0m" 2>&1 | tee -a $LOGFILE
    dappnode_core_start

    echo -e "\n\e[33mWaiting for VPN initialization...\e[0m"
    sleep 10

    echo -e "\n\e[32m##############################################\e[0m"
    echo -e "\e[32m#      DAppNode VPN Access Credentials        #\e[0m"
    echo -e "\e[32m##############################################\e[0m"
    echo -e "\n\e[1mYour DAppNode is ready! Connect using your preferred VPN client.\e[0m"
    echo -e "\e[1mChoose either Wireguard (recommended) or OpenVPN and import the\e[0m"
    echo -e "\e[1mcredentials below into your VPN app to access your DAppNode.\e[0m\n"

    echo -e "\e[1m--- Wireguard ---\e[0m"
    dappnode_wireguard --localhost 2>&1 || \
        echo -e "\e[33mWireguard credentials not yet available. Try later with: dappnode_wireguard --localhost\e[0m"

    echo -e "\n\e[1m--- OpenVPN ---\e[0m"
    dappnode_openvpn_get dappnode_admin --localhost 2>&1 || \
        echo -e "\e[33mOpenVPN credentials not yet available. Try later with: dappnode_openvpn_get dappnode_admin --localhost\e[0m"

    echo -e "\n\e[32mImport the configuration above into your VPN client of choice to access your DAppNode at http://my.dappnode\e[0m"
fi

exit 0
