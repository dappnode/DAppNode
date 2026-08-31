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

# ICMP is filtered on many corporate, hotel and cloud networks, so a failed
# ping alone does not mean the machine is offline. Confirm over HTTPS before
# declaring the installation broken.
check_connectivity() {
    ping -c 1 -q google.com >/dev/null 2>&1 && return 0

    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 10 -o /dev/null https://www.google.com/generate_204 && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q --timeout=10 -O /dev/null https://www.google.com/generate_204 && return 0
    fi

    # Neither downloader is guaranteed to be present this early, so fall back to
    # a plain TCP connect, which bash can do on its own.
    if (exec 3<>/dev/tcp/www.google.com/443) 2>/dev/null; then
        exec 3<&- 3>&-
        return 0
    fi

    return 1
}

components=(BIND IPFS VPN DAPPMANAGER WIFI)
detect_installation_type
if check_connectivity; then
    echo -e "\e[32m Connectivity OK\n \e[0m"
else
    error_exit
fi

if docker -v >/dev/null 2>&1; then
    echo -e "\e[32m Docker installed ok\e[0m"
else
    error_exit
fi

if docker compose -v >/dev/null 2>&1; then
    echo -e "\e[32m docker compose installed ok\e[0m"
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
    # shellcheck disable=SC2028
    docker save "$img" >/dev/null && echo -ne "\e[32mImage $img OK\n\e[0m" || echo "\e[31mImage $img Corrupted!\n\e[0m"
done

rm -f /usr/src/dappnode/.firstboot
read -r -p "Test completed successfully. Press enter to continue"
