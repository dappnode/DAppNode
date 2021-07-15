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
    # shellcheck disable=SC1090
    source "${PROFILE_FILE}" &>/dev/null

    # Stop DAppNode containers
    docker container stop "$(docker ps --format '{{.Names}}' | grep DAppNode)" || echo "containers already stopped"
    # Remove DAppNode containers
    docker container rm "$(docker ps -a --format '{{.Names}}' | grep DAppNode)" || echo "containers already removed"
    # Remove DAppNode images
    docker image rm "$(docker image ls -a | grep "dappnode")" || echo "images already removed"
    # Remove DAppNode volumes
    docker volume rm "$(docker volume ls | grep "dappnode\|dncore")" || echo "packages already removed"

    # Remove containers, volumes and images
    docker-compose "$DNCORE_YMLS" down --rmi 'all' -v || echo "packages already removed"

    # Remove dncore_network
    docker network remove dncore_network || echo "dncore_network already removed"

    # Remove dir
    rm -rf /usr/src/dappnode

    # Remove profile file
    USER=$(grep 1000 /etc/passwd | cut -f 1 -d:)
    [ -n "$USER" ] && PROFILE=/home/$USER/.profile || PROFILE=/root/.profile
    sed -i '/########          DAPPNODE PROFILE          ########/g' $PROFILE
    sed -i '/.*dappnode_profile/g' $PROFILE

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
