#!/usr/bin/env bash
DAPPNODE_DIR="/usr/src/dappnode"
DAPPNODE_CORE_DIR="${DAPPNODE_DIR}/DNCORE"
PROFILE_FILE="${DAPPNODE_CORE_DIR}/.dappnode_profile"
input=$1 # Allow to call script with argument (must be Y/N)

[ -f $PROFILE_FILE ] || (
    echo "Error: DAppNode profile does not exist."
    exit 1
)

uninstall() {
    echo -e "\e[32mUninstalling DAppNode\e[0m"
    # shellcheck disable=SC1090
    source "${PROFILE_FILE}" &>/dev/null

    DAPPNODE_CONTAINERS="$(docker ps -a --format '{{.Names}}' | grep DAppNode)"
    echo -e "\e[32mRemoving DAppNode containers: \e[0m\n${DAPPNODE_CONTAINERS}"
    for container in $DAPPNODE_CONTAINERS; do
        # Stop DAppNode container
        docker stop "$container" &>/dev/null
        # Remove DAppNode container
        docker rm "$container" &>/dev/null
    done

    DAPPNODE_IMAGES="$(docker image ls -a | grep "dappnode")"
    echo -e "\e[32mRemoving DAppNode images: \e[0m\n${DAPPNODE_IMAGES}"
    for image in $DAPPNODE_IMAGES; do
        # Remove DAppNode images
        docker image rm "$image" &>/dev/null
    done

    DAPPNODE_VOLUMES="$(docker volume ls | grep "dappnode\|dncore")"
    echo -e "\e[32mRemoving DAppNode volumes: \e[0m\n${DAPPNODE_VOLUMES}"
    for volume in $DAPPNODE_VOLUMES; do
        # Remove DAppNode volumes
        docker volume rm "$volume" &>/dev/null
    done

    # Remove dncore_network
    echo -e "\e[32mRemoving docker dncore_network\e[0m"
    docker network remove dncore_network || echo "dncore_network already removed"

    # Remove dir
    echo -e "\e[32mRemoving DAppNode directory\e[0m"
    rm -rf /usr/src/dappnode

    # Remove profile file
    USER=$(grep 1000 /etc/passwd | cut -f 1 -d:)
    [ -n "$USER" ] && PROFILE=/home/$USER/.profile || PROFILE=/root/.profile
    sed -i '/########          DAPPNODE PROFILE          ########/g' $PROFILE
    sed -i '/.*dappnode_profile/g' $PROFILE

    echo -e "\e[32mDAppNode uninstalled!\e[0m"
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
