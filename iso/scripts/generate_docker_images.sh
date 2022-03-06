#!/bin/bash

# shellcheck disable=SC1091
source /usr/src/app/.dappnode_profile

echo "Cleaning previous files"
rm -rf ./DNP_*

# Curl github release with version

echo "Downloading source code & building DNP_WIREGUARD..."
curl -LJO https://github.com/dappnode/DNP_WIREGUARD/archive/refs/tags/"v${WIREGUARD_VERSION}.tar.gz" || { echo "Failed to download DNP_WIREGUARD"; exit 1; }
mkdir DNP_WIREGUARD
tar -xzf "DNP_WIREGUARD-${WIREGUARD_VERSION}.tar.gz" -C ./DNP_WIREGUARD --strip-components=1 || { echo "Failed to extract DNP_WIREGUARD"; exit 1; }
docker-compose -f ./DNP_WIREGUARD/docker-compose.yml build || { echo "Failed to build DNP_WIREGUARD"; exit 1; }
docker save wireguard.dnp.dappnode.eth:"${WIREGUARD_VERSION}" | xz -e9vT0 >/images/wireguard.dnp.dappnode.eth_"${WIREGUARD_VERSION}"_linux-amd64.txz ||  { echo "Failed to save DNP_WIREGUARD"; exit 1; }

echo "Downloading source code & building DNP_HTTPS..."    
curl -LJO https://github.com/dappnode/DNP_HTTPS/archive/refs/tags/"v${HTTPS_VERSION}.tar.gz" || { echo "Failed to download DNP_HTTPS"; exit 1; }
mkdir DNP_HTTPS 
tar -xzf "DNP_HTTPS-${HTTPS_VERSION}.tar.gz"  -C ./DNP_HTTPS --strip-components=1 || { echo "Failed to extract DNP_HTTPS"; exit 1; }
docker-compose -f ./DNP_HTTPS/docker-compose.yml build || { echo "Failed to build DNP_HTTPS"; exit 1; }
docker save https.dnp.dappnode.eth: "${HTTPS_VERSION}" | xz -e9vT0 >/images/https.dnp.dappnode.eth_"${HTTPS_VERSION}"_linux-amd64.txz || { echo "Failed to save DNP_HTTPS"; exit 1; }

echo "Downloading source code & building DNP_IPFS..."
curl -LJO https://github.com/dappnode/DNP_IPFS/archive/refs/tags/"v${IPFS_VERSION}.tar.gz" || { echo "Failed to download DNP_IPFS"; exit 1; }
mkdir DNP_IPFS
tar -xzf "DNP_IPFS-${IPFS_VERSION}.tar.gz" -C ./DNP_IPFS --strip-components=1 || { echo "Failed to extract DNP_IPFS"; exit 1; }
docker-compose -f ./DNP_IPFS/docker-compose.yml build || { echo "Failed to build DNP_IPFS"; exit 1; }
docker save ipfs.dnp.dappnode.eth:"${IPFS_VERSION}" | xz -e9vT0 >/images/ipfs.dnp.dappnode.eth_"${IPFS_VERSION}"_linux-amd64.txz || { echo "Failed to save DNP_IPFS"; exit 1; }

echo "Downloading source code & building DNP_BIND..."
curl -LJO https://github.com/dappnode/DNP_BIND/archive/refs/tags/"v${BIND_VERSION}.tar.gz" || { echo "Failed to download DNP_BIND"; exit 1; }
mkdir DNP_BIND 
tar -xzf "DNP_BIND-${BIND_VERSION}.tar.gz" -C ./DNP_BIND --strip-components=1 || { echo "Failed to extract DNP_BIND"; exit 1; }
docker-compose -f ./DNP_BIND/docker-compose.yml build || { echo "Failed to build DNP_BIND"; exit 1; }
docker save bind.dnp.dappnode.eth:"${BIND_VERSION}" | xz -e9vT0 >/images/bind.dnp.dappnode.eth_"${BIND_VERSION}"_linux-amd64.txz || { echo "Failed to save DNP_BIND"; exit 1; }

echo "Downloading source code & building DNP_DAPPMANAGER..."
curl -LJO https://github.com/dappnode/DNP_DAPPMANAGER/archive/refs/tags/"v${DAPPMANAGER_VERSION}.tar.gz" || { echo "Failed to download DNP_DAPPMANAGER"; exit 1; }
mkdir DNP_DAPPMANAGER 
tar -xzf "DNP_DAPPMANAGER-${DAPPMANAGER_VERSION}.tar.gz" -C ./DNP_DAPPMANAGER --strip-components=1 || { echo "Failed to extract DNP_DAPPMANAGER"; exit 1; }
docker-compose -f ./DNP_DAPPMANAGER/docker-compose.yml build || { echo "Failed to build DNP_DAPPMANAGER"; exit 1; }
docker save dappmanager.dnp.dappnode.eth:"${DAPPMANAGER_VERSION}" | xz -e9vT0 >/images/dappmanager.dnp.dappnode.eth_"${DAPPMANAGER_VERSION}"_linux-amd64.txz || { echo "Failed to save DNP_DAPPMANAGER"; exit 1; }

echo "Downloading source code & building DNP_WIFI..."
curl -LJO https://github.com/dappnode/DNP_WIFI/archive/refs/tags/"v${WIFI_VERSION}.tar.gz" || { echo "Failed to download DNP_WIFI"; exit 1; }
mkdir DNP_WIFI 
tar -xzf "DNP_WIFI-${WIFI_VERSION}.tar.gz" -C ./DNP_WIFI --strip-components=1 || { echo "Failed to extract DNP_WIFI"; exit 1; }
docker-compose -f ./DNP_WIFI/docker-compose.yml build || { echo "Failed to build DNP_WIFI"; exit 1; }
docker save wifi.dnp.dappnode.eth:"${WIFI_VERSION}" | xz -e9vT0 >/images/wifi.dnp.dappnode.eth_"${WIFI_VERSION}"_linux-amd64.txz || { echo "Failed to save DNP_WIFI"; exit 1; }

echo "Coping dappnode_all_docker_images_linux-amd64.txz to dappnode dir..."
cp /images/* /usr/src/app/dappnode/

echo "Finished!"
