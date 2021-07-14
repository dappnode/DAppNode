#!/bin/bash

HOME=${HOME:-/home/dappnode}
DAPPNODE_DIR="/usr/src/dappnode"

error_exit() {
    echo -e "\e[31m Error on installation!!! \n \e[0m"
    read -r -p "Check installation source. Press enter to continue"
    exit 1
}
SERIAL=$(dmidecode -s system-serial-number)
echo "DAppNode Installation Test"
date
echo "Serial: ${SERIAL}"
echo "################################"

# TEMPORARY: think a way to integrate flags instead of use files to detect installation type
detect_installation_type() {
    # Check for old and new location of iso_install.log
    if [ -f "${DAPPNODE_DIR}/iso_install.log" ] || [ -f "${DAPPNODE_DIR}/logs/iso_install.log" ]; then
        components=(BIND IPFS WIREGUARD DAPPMANAGER WIFI HTTPS)
    fi
}

components=(BIND IPFS VPN DAPPMANAGER WIFI)
detect_installation_type
if ping -c 1 -q google.com >&/dev/null; then
    echo -e "\e[32m Connectivity OK\n \e[0m"
else
    error_exit
fi

if docker -v >/dev/null 2>&1; then
    echo -e "\e[32m Docker installed ok\e[0m"
else
    error_exit
fi

if docker-compose -v >/dev/null 2>&1; then
    echo -e "\e[32m docker-compose installed ok\e[0m"
else
    error_exit
fi

for comp in "${components[@]}"; do
    if docker images | grep "${comp,,}" >/dev/null 2>&1; then
        echo -e "\e[32m ${comp} docker image loaded ok\e[0m"
    else
        echo -e "\e[31m ${comp} docker image not loaded ok!\e[0m"
        error_exit
    fi
done

echo -e "\e[32m docker image versions:\e[0m"
docker images | grep dappnode | awk '{print $1, $2}'

echo -e "\e[32m doing docker image integrity test...\e[0m"
imgs=$(docker images | grep dappnode | awk '{print $3}')

for img in $imgs; do
    docker save $img >/dev/null && echo -ne "\e[32mImage $img OK\n\e[0m" || echo "\e[31mImage $img Corrupted!\n\e[0m"
done

rm -f /usr/src/dappnode/.firstboot
read -r -p "Test completed successfully. Press enter to continue"
