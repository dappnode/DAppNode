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

# Color output helper (no ANSI on macOS to avoid \e issues)
color_echo() {
    local color="$1"; shift
    if $IS_LINUX; then
        case "$color" in
            green) code="\e[32m" ;;
            yellow) code="\e[33m" ;;
            *) code="" ;;
        esac
        echo -e "${code}$*\e[0m"
    else
        echo "$*"
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

[ -f "$PROFILE_FILE" ] || {
    echo "Error: DAppNode profile does not exist at ${PROFILE_FILE}."
    exit 1
}

uninstall() {
    color_echo green "Uninstalling DAppNode"
    # shellcheck disable=SC1090
    source "${PROFILE_FILE}" &>/dev/null

    DAPPNODE_CONTAINERS="$(docker ps -a --format '{{.Names}}' | grep DAppNode)"
    color_echo green "Removing DAppNode containers: "
    echo "${DAPPNODE_CONTAINERS}"
    for container in $DAPPNODE_CONTAINERS; do
        # Stop DAppNode container
        docker stop "$container" &>/dev/null
        # Remove DAppNode container
        docker rm "$container" &>/dev/null
    done

    DAPPNODE_IMAGES="$(docker image ls -a | grep "dappnode")"
    color_echo green "Removing DAppNode images: "
    echo "${DAPPNODE_IMAGES}"
    for image in $DAPPNODE_IMAGES; do
        # Remove DAppNode images
        docker image rm "$image" &>/dev/null
    done

    DAPPNODE_VOLUMES="$(docker volume ls | grep "dappnode\|dncore")"
    color_echo green "Removing DAppNode volumes: "
    echo "${DAPPNODE_VOLUMES}"
    for volume in $DAPPNODE_VOLUMES; do
        # Remove DAppNode volumes
        docker volume rm "$volume" &>/dev/null
    done

    # Remove dncore_network
    color_echo green "Removing docker dncore_network"
    docker network remove dncore_network || echo "dncore_network already removed"

    # Remove DAppNode directory
    color_echo green "Removing DAppNode directory: ${DAPPNODE_DIR}"
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

    color_echo green "DAppNode uninstalled!"
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
