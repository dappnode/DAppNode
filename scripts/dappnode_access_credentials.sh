#!/bin/bash

# This script will iterate over the access methods in dappnode
# and return the credentials for each service available

#############
#0.VARIABLES#
#############
# Containers
DAPPMANAGER_CONTAINER="DAppNodeCore-dappmanager.dnp.dappnode.eth"
WIFI_CONTAINER="DAppNodeCore-wifi.dnp.dappnode.eth"
WIREGUARD_CONTAINER="DAppNodeCore-api.wireguard.dnp.dappnode.eth"
OPENVPN_CONTAINER="DAppNodeCore-vpn.dnp.dappnode.eth"
HTTPS_CONTAINER="DAppNodeCore-https.dnp.dappnode.eth"
# Credentials
WIREGUARD_GET_CREDS="docker exec -i $WIREGUARD_CONTAINER getWireguardCredentials"
OPENVPN_GET_CREDS="docker exec -i $OPENVPN_CONTAINER getAdminCredentials"
WIFI_GET_CREDS=$(grep 'SSID\|WPA_PASSPHRASE' /usr/src/dappnode/DNCORE/docker-compose-wifi.yml)
# Endpoints
AVAHI_ENDPOINT="dappnode.local"
DAPPNODE_ADMINUI_URL="http://my.dappnode"
DAPPNODE_ADMINUI_LOCAL_URL="http://${AVAHI_ENDPOINT}"
DAPPNODE_WELCOME_URL="http://welcome.dappnode.io"

#############
#1.FUNCTIONS#
#############

function dappnode_startup_check () {
  echo -ne "Checking DAppNode connectivity methods (press ctrl+c to stop)...\n"
  n=0
  until [ "$n" -ge 8 ]
  do
    [ "$(docker inspect -f '{{.State.Running}}' ${DAPPMANAGER_CONTAINER} 2> /dev/null)" = "true" ] && break
    n=$((n+1))
    echo -n "."
    sleep 4
  done
}

# $1 Connection method $2 Credentials
function create_connection_message () {
  echo -e "\e[32mConnect to DAppNode through $1 using the following credentials:\e[0m\n$2\n\nAccess your DAppNode at \e[4m$DAPPNODE_ADMINUI_URL\e\n\n[0mDiscover more ways to connect to your DAppNode at \e[4m$DAPPNODE_WELCOME_URL\e[0m"
}

function wifi_connection () {
  # NOTE: network interface may be in use by host => $(cat /sys/class/net/${INTERFACE}/operstate)" !== "up")
  # NOTE: wifi has a delay up to 1 min
  # wifi container running
  [ "$(docker inspect -f '{{.State.Running}}' ${WIFI_CONTAINER} 2> /dev/null)" = "true" ] && \
  # Check interface variable is set
  [ -n "$(docker exec -it $WIFI_CONTAINER iw dev | grep 'Interface' | awk 'NR==1{print $2}')" ] && \
  create_connection_message "Wi-Fi" "$WIFI_GET_CREDS" || \
  echo -e "\e[33mWifi not detected\e[0m"
}

function avahi_connection () {
  avahi-resolve -n $AVAHI_ENDPOINT > /dev/null 2>&1 && \
  # Https container exists
  # shellcheck disable=SC2143
  [ "$(docker ps -a | grep ${HTTPS_CONTAINER})" ] && \
  # Https container running
  [ "$(docker inspect -f '{{.State.Running}}' ${HTTPS_CONTAINER})" = "true" ] && \
  # Https env variable LOCAL_PROXYING="true"
  [ "$(docker exec -i ${HTTPS_CONTAINER} sh -c 'echo "$LOCAL_PROXYING"')" = "true" ] && \
  # avahi-daemon running => systemctl is-active avahi-daemon RETURNS "active" or "inactive"
  [ "$(systemctl is-active avahi-daemon)" = "active" ] && \
  echo -e "\n\e[32mConnect to DAppNode through Local Proxying.\e[0m\n\nVisit \e[4m$DAPPNODE_ADMINUI_LOCAL_URL\e\n\n[0mCheck out all the access methods available to connect to your DAppNode at \e[4m$DAPPNODE_WELCOME_URL\e[0m\n" || \
  echo -e "\e[33mLocal Proxy not detected\e[0m"
}

function wireguard_connection () {
  # wireguard container exists
  # shellcheck disable=SC2143
  [ "$(docker ps -a | grep ${WIREGUARD_CONTAINER})" ] && \
  # wireguard container running
  [ "$(docker inspect -f '{{.State.Running}}' ${WIREGUARD_CONTAINER})" = "true" ] && \
  create_connection_message "Wireguard" "$($WIREGUARD_GET_CREDS)" || \
  echo -e "\e[33mWireguard not detected\e[0m"
}

function openvpn_connection () {
  # openvpn container exists
  # shellcheck disable=SC2143
  [ "$(docker ps -a | grep ${OPENVPN_CONTAINER})" ] && \
  # openvpn container running
  [ "$(docker inspect -f '{{.State.Running}}' ${OPENVPN_CONTAINER})" = "true" ] && \
  create_connection_message "Open-VPN" "$($OPENVPN_GET_CREDS)" || \
  echo -e "\e[33mOpen VPN not detected\e[0m"
}

function line_separator () {
  echo "====================="
}

########
#2.MAIN#
########

dappnode_startup_check
line_separator
wifi_connection
line_separator
avahi_connection
line_separator
wireguard_connection
line_separator
openvpn_connection

exit 0
