#!/usr/bin/env bash

# This uninstaller is written for bash. It's safe to *run it from zsh* (it will execute via bash
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
# Dirs — macOS uses $HOME/dappnode, Linux uses /usr/src/dappnode (mirrors install script)
if $IS_MACOS; then
    DAPPNODE_DIR="$HOME/dappnode"
else
    DAPPNODE_DIR="/usr/src/dappnode"
fi
DAPPNODE_CORE_DIR="${DAPPNODE_DIR}/DNCORE"
PROFILE_FILE="${DAPPNODE_CORE_DIR}/.dappnode_profile"
input=$1 # Allow to call script with argument (must be Y/N)

##############################
# Cross-platform Helpers     #
##############################

# Cross-platform in-place sed (macOS requires '' after -i)
sed_inplace() {
    if $IS_MACOS; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

[ -f "$PROFILE_FILE" ] || {
    echo "Error: DAppNode profile does not exist at ${PROFILE_FILE}."
    exit 1
}

uninstall() {
    echo "Uninstalling DAppNode"
    # shellcheck disable=SC1090
    source "${PROFILE_FILE}" &>/dev/null

    DAPPNODE_CONTAINERS="$(docker ps -a --format '{{.Names}}' | grep DAppNode)"
    echo "Removing DAppNode containers: "
    echo "${DAPPNODE_CONTAINERS}"
    for container in $DAPPNODE_CONTAINERS; do
        # Stop DAppNode container
        docker stop "$container" &>/dev/null
        # Remove DAppNode container
        docker rm "$container" &>/dev/null
    done

    DAPPNODE_IMAGES="$(docker image ls -a | grep "dappnode")"
    echo "Removing DAppNode images: "
    echo "${DAPPNODE_IMAGES}"
    for image in $DAPPNODE_IMAGES; do
        # Remove DAppNode images
        docker image rm "$image" &>/dev/null
    done

    DAPPNODE_VOLUMES="$(docker volume ls | grep "dappnode\|dncore")"
    echo "Removing DAppNode volumes: "
    echo "${DAPPNODE_VOLUMES}"
    for volume in $DAPPNODE_VOLUMES; do
        # Remove DAppNode volumes
        docker volume rm "$volume" &>/dev/null
    done

    # Remove dncore_network dnprivate_network dnpublic_network gnosis_network holesky_network hoodi_network lukso_network mainnet_network prater_network sepolia_network starknet_network starknet_sepolia_network
    echo "Removing dappnode networks..."
    docker network remove dncore_network dnprivate_network dnpublic_network gnosis_network holesky_network hoodi_network lukso_network mainnet_network prater_network sepolia_network starknet_network starknet_sepolia_network &>/dev/null || true

    # Clean up host DNS resolution artifacts (--resolve-from-host)
    if $IS_LINUX; then
        # systemd-resolved path: remove service, timer, and script
        if [ -f /etc/systemd/system/dappnode-dns.timer ]; then
            echo "Removing dappnode-dns systemd timer and service..."
            systemctl disable dappnode-dns.timer 2>/dev/null || true
            systemctl stop dappnode-dns.timer 2>/dev/null || true
            systemctl disable dappnode-dns.service 2>/dev/null || true
            systemctl stop dappnode-dns.service 2>/dev/null || true
            rm -f /etc/systemd/system/dappnode-dns.service
            rm -f /etc/systemd/system/dappnode-dns.timer
            rm -f /usr/local/bin/dappnode-dns.sh
            systemctl daemon-reload || true
        fi

        # dnsmasq path: remove dappnode config and restore resolv.conf
        if [ -f /etc/dnsmasq.d/dappnode.conf ]; then
            echo "Removing dnsmasq DAppNode config..."
            rm -f /etc/dnsmasq.d/dappnode.conf
            systemctl restart dnsmasq 2>/dev/null || true
        fi
        if [ -f /etc/resolv.conf.dappnode.bak ]; then
            echo "Restoring /etc/resolv.conf from backup..."
            cp /etc/resolv.conf.dappnode.bak /etc/resolv.conf
            rm -f /etc/resolv.conf.dappnode.bak
        fi
    fi

    # Remove DAppNode directory
    echo "Removing DAppNode directory: ${DAPPNODE_DIR}"
    rm -rf "${DAPPNODE_DIR}"

    # Remove profile file references from shell config files
    local user_home
    local shell_configs

    if $IS_MACOS; then
        user_home="$HOME"
        # macOS defaults to zsh — matches install script
        shell_configs=(".zshrc" ".zprofile")
    else
        local user_name
        user_name=$(grep 1000 /etc/passwd | cut -f 1 -d:)
        if [ -n "$user_name" ]; then
            user_home="/home/$user_name"
        else
            user_home="/root"
        fi
        shell_configs=(".profile" ".bashrc")
    fi

    # Remove Dappnode profile references from shell config files
    for config_file in "${shell_configs[@]}"; do
        local config_path="${user_home}/${config_file}"
        if [ -f "$config_path" ]; then
            sed_inplace '/########          DAPPNODE PROFILE          ########/d' "$config_path"
            sed_inplace '/.*dappnode_profile/d' "$config_path"
        fi
    done

    echo "DAppNode uninstalled!"
}

if [ $# -eq 0 ]; then
    read -r -p "WARNING: This script will uninstall and delete all DAppNode
containers and volumes. Are You Sure? [Y/n] " input <&2
fi


case $input in
[yY][eE][sS] | [yY])
    uninstall
    ;;
[nN][oO] | [nN])
    echo "Ok."
    ;;
*)
    echo "Invalid input. Exiting..."
    exit 1
    ;;
esac
