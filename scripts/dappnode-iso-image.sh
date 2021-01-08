#!/bin/bash

INSTALLER_URL="https://github.com/dappnode/DAppNode_Installer.git"
INSTALLER_DIR="DAppNode_Installer"

## 1. Which core packages to be updated?

read -p "DAPPMANAGER will be updated? (Y/N)  " DAPPMANAGER_CONFIRM
if [[ $DAPPMANAGER_CONFIRM == [yY] ]]
then 
    read -p "which git tag?  " DAPPMANAGER_TAG
fi

read -p "BIND will be updated? (Y/N)  " BIND_CONFIRM
if [[ $BIND_CONFIRM == [yY] ]]
then 
    read -p "which git tag?  " BIND_TAG
fi

read -p "IPFS will be updated? (Y/N)  " IPFS_CONFIRM
if [[ $IPFS_CONFIRM == [yY] ]]
then 
    read -p "which git tag?  " IPFS_TAG
fi

read -p "VPN will be updated? (Y/N)  " VPN_CONFIRM
if [[ $VPN_CONFIRM == [yY] ]]
then 
    read -p "which git tag?  " VPN_TAG
fi

read -p "WIFI will be updated? (Y/N)  " WIFI_CONFIRM
if [[ $WIFI_CONFIRM == [yY] ]]
then 
    read -p "which git tag?  " WIFI_TAG
fi

## 2. clone installer repo 

# 1 -> core package  2 -> package tag 
function set_new_tag () {
    sed -i -e 's/'"$1"'_VERSION:-[0-9,.]\+/'"$1"'_VERSION:-'"$2"'/' build/scripts/.dappnode_profile ## Improve substitution: exclude } and " chars 
}

git clone "$INSTALLER_URL"
cd "$INSTALLER_DIR" || return

if [ -n "$DAPPMANAGER_TAG" ]
then
   set_new_tag "DAPPMANAGER" "$DAPPMANAGER_TAG"
fi 

if [ -n "$BIND_TAG" ]
then
   set_new_tag "BIND" "$BIND_TAG"
fi 

if [ -n "$IPFS_TAG" ]
then
   set_new_tag "IPFS" "$IPFS_TAG"
fi 

if [ -n "$VPN_TAG" ]
then
   set_new_tag "VPN" "$VPN_TAG"
fi 

if [ -n "$WIFI_TAG" ]
then
   set_new_tag "WIFI" "$WIFI_TAG"
fi 

echo "Successfully changed core packages tags in .dappnode_profile"

## 3. Create ISO image

docker-compose build --no-cache
docker-compose up

## 4. Get ISO image and isolate it

cp images/DAppNode-debian-bullseye-amd64.iso ../
cd ..
rm -rf "$INSTALLER_DIR"
