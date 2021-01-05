#!/bin/bash

## This script automates the process of a "core update". ?? watchgit dnp_core?

DAPPMANAGER_URL="https://github.com/dappnode/DNP_DAPPMANAGER.git"
DAPPMANAGER_DIR="DNP_DAPPMANAGER"

BIND_URL="https://github.com/dappnode/DNP_BIND.git"
BIND_DIR="DNP_BIND"

VPN_URL="https://github.com/dappnode/DNP_VPN.git"
VPN_DIR="DNP_VPN"

WIFI_URL="https://github.com/dappnode/DNP_WIFI.git"
WIFI_DIR="DNP_WIFI"

IPFS_URL="https://github.com/dappnode/DNP_IPFS.git"
IPFS_DIR="DNP_IPFS"

CORE_URL="https://github.com/dappnode/DNP_CORE.git"
CORE_DIR="DNP_CORE"

## 1. Which core packages to be updated?

read -p "DAPPMANAGER will be updated? (Y/N)  " DAPPMANAGER_CONFIRM
if [[ $DAPPMANAGER_CONFIRM == [yY] ]]
then 
    read -p "which git branch?  " DAPPMANAGER_BRANCH
fi

read -p "BIND will be updated? (Y/N)  " BIND_CONFIRM
if [[ $BIND_CONFIRM == [yY] ]]
then 
    read -p "which git branch?  " BIND_BRANCH
fi

read -p "WIFI will be updated? (Y/N)  " WIFI_CONFIRM
if [[ $WIFI_CONFIRM == [yY] ]]
then 
    read -p "which git branch?  " WIFI_BRANCH
fi

read -p "IPFS will be updated? (Y/N)  " IPFS_CONFIRM
if [[ $IPFS_CONFIRM == [yY] ]]
then 
    read -p "which git branch?  " IPFS_BRANCH
fi

read -p "VPN will be updated? (Y/N)  " VPN_CONFIRM
if [[ $VPN_CONFIRM == [yY] ]]
then 
    read -p "which git branch?  " VPN_BRANCH
fi

## 2. clone repo and sdk build and Get IPFS of those packages

# 1-> SDK output
function parse_ipfs {
    HASH="Release hash : "
    if echo "$1" | grep -q "$HASH"
    then
        echo "matched"
        STR="$1"
        IPFS_HASH=${STR%http:*}
        IPFS_HASH=${IPFS_HASH##*Release hash : }
        IPFS_HASH=${IPFS_HASH//[$'\t\r\n ']}
    else 
        echo "no matched"
    fi 
}

# 1-> DIR | 2-> BRANCH | 3-> URL
function clone_repo {
    echo "Cloning $1, branch: $2"
    git clone -b "$2" "$3" || echo "Branch not found" exit 1
}

# 1-> DIR
function sdk_build {
    cd "$1" || return
    echo "Creating IPFS, this may take a while..."
    SDK=$(dappnodesdk build)
    cd ..
}

if [ -n "$DAPPMANAGER_BRANCH" ]
then
    clone_repo "$DAPPMANAGER_DIR" "$DAPPMANAGER_BRANCH" "$DAPPMANAGER_URL"
    sdk_build "$DAPPMANAGER_DIR"
    parse_ipfs "$SDK"
    DAPPMANAGER_IPFS_HASH="$IPFS_HASH"
fi 

if [ -n "$BIND_BRANCH" ]
then
    clone_repo "$BIND_DIR" "$BIND_BRANCH" "$BIND_URL"
    sdk_build "$BIND_DIR"
    parse_ipfs "$SDK"
    BIND_IPFS_HASH="$IPFS_HASH"
fi

if [ -n "$WIFI_BRANCH" ]
then
    clone_repo "$WIFI_DIR" "$WIFI_BRANCH" "$WIFI_URL"
    sdk_build "$WIFI_DIR"
    parse_ipfs "$SDK"
    WIFI_IPFS_HASH="$IPFS_HASH"
fi

if [ -n "$VPN_BRANCH" ]
then
    clone_repo "$VPN_DIR" "$VPN_BRANCH" "$VPN_URL"
    sdk_build "$VPN_DIR"
    parse_ipfs "$SDK"
    VPN_IPFS_HASH="$IPFS_HASH"
fi

if [ -n "$IPFS_BRANCH" ]
then
    clone_repo "$IPFS_DIR" "$IPFS_BRANCH" "$IPFS_URL"
    sdk_build "$IPFS_DIR"
    parse_ipfs "$SDK"
    IPFS_IPFS_HASH="$IPFS_HASH"
fi

rm -rf "$DAPPMANAGER_DIR" "$BIND_DIR" "$VPN_DIR" "$IPFS_DIR" "$WIFI_DIR"

echo "HASHES: $IPFS_IPFS_HASH $BIND_IPFS_HASH $WIFI_IPFS_HASH $VPN_IPFS_HASH $DAPPMANAGER_IPFS_HASH"

## 3. Edit manifest of dnp_core with the IPFS

clone_repo "$CORE_DIR" "master" "$CORE_URL"
cd "$CORE_DIR" || return

if [ -n "$DAPPMANAGER_BRANCH" ]
then
    cat dappnode_package.json | jq -r '."dependencies"."dappmanager.dnp.dappnode.eth"='\""$DAPPMANAGER_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
fi

if [ -n "$BIND_BRANCH" ]
then
    cat dappnode_package.json | jq -r '."dependencies"."bind.dnp.dappnode.eth"='\""$BIND_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
fi

if [ -n "$VPN_BRANCH" ]
then
    cat dappnode_package.json | jq -r '."dependencies"."vpn.dnp.dappnode.eth"='\""$VPN_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
fi

if [ -n "$WIFI_BRANCH" ]
then
    cat dappnode_package.json | jq -r '."dependencies"."wifi.dnp.dappnode.eth"='\""$WIFI_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
fi

if [ -n "$IPFS_BRANCH" ]
then
   cat dappnode_package.json | jq -r '."dependencies"."ipfs.dnp.dappnode.eth"='\""$IPFS_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
fi

## 4. sdk build and return IPFS of DNP_CORE to be installed

dappnodesdk build