#!/bin/bash

function core_update() {
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

    read -p "DAPPMANAGER will be updated? (Y/N)  " DAPPMANAGER_CONFIRM_CORE
    if [[ $DAPPMANAGER_CONFIRM_CORE == [yY] ]]
    then 
        read -p "which git branch?  " DAPPMANAGER_BRANCH
    fi

    read -p "BIND will be updated? (Y/N)  " BIND_CONFIRM_CORE
    if [[ $BIND_CONFIRM_CORE == [yY] ]]
    then 
        read -p "which git branch?  " BIND_BRANCH
    fi

    read -p "WIFI will be updated? (Y/N)  " WIFI_CONFIRM_CORE
    if [[ $WIFI_CONFIRM_CORE == [yY] ]]
    then 
        read -p "which git branch?  " WIFI_BRANCH
    fi

    read -p "IPFS will be updated? (Y/N)  " IPFS_CONFIRM_CORE
    if [[ $IPFS_CONFIRM_CORE == [yY] ]]
    then 
        read -p "which git branch?  " IPFS_BRANCH
    fi

    read -p "VPN will be updated? (Y/N)  " VPN_CONFIRM_CORE
    if [[ $VPN_CONFIRM_CORE == [yY] ]]
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

    if [ -v DAPPMANAGER_BRANCH ]
    then
        clone_repo "$DAPPMANAGER_DIR" "$DAPPMANAGER_BRANCH" "$DAPPMANAGER_URL"
        sdk_build "$DAPPMANAGER_DIR"
        parse_ipfs "$SDK"
        DAPPMANAGER_IPFS_HASH="$IPFS_HASH"
    fi 

    if [ -v BIND_BRANCH ]
    then
        clone_repo "$BIND_DIR" "$BIND_BRANCH" "$BIND_URL"
        sdk_build "$BIND_DIR"
        parse_ipfs "$SDK"
        BIND_IPFS_HASH="$IPFS_HASH"
    fi

    if [ -v WIFI_BRANCH ]
    then
        clone_repo "$WIFI_DIR" "$WIFI_BRANCH" "$WIFI_URL"
        sdk_build "$WIFI_DIR"
        parse_ipfs "$SDK"
        WIFI_IPFS_HASH="$IPFS_HASH"
    fi

    if [ -v VPN_BRANCH ]
    then
        clone_repo "$VPN_DIR" "$VPN_BRANCH" "$VPN_URL"
        sdk_build "$VPN_DIR"
        parse_ipfs "$SDK"
        VPN_IPFS_HASH="$IPFS_HASH"
    fi

    if [ -v IPFS_BRANCH ]
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

    if [ -v DAPPMANAGER_BRANCH ]
    then
        cat dappnode_package.json | jq -r '."dependencies"."dappmanager.dnp.dappnode.eth"='\""$DAPPMANAGER_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
    fi

    if [ -v BIND_BRANCH ]
    then
        cat dappnode_package.json | jq -r '."dependencies"."bind.dnp.dappnode.eth"='\""$BIND_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
    fi

    if [ -v VPN_BRANCH ]
    then
        cat dappnode_package.json | jq -r '."dependencies"."vpn.dnp.dappnode.eth"='\""$VPN_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
    fi

    if [ -v WIFI_BRANCH ]
    then
        cat dappnode_package.json | jq -r '."dependencies"."wifi.dnp.dappnode.eth"='\""$WIFI_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
    fi

    if [ -v IPFS_BRANCH ]
    then
    cat dappnode_package.json | jq -r '."dependencies"."ipfs.dnp.dappnode.eth"='\""$IPFS_IPFS_HASH"\"'' dappnode_package.json|sponge dappnode_package.json
    fi

    ## 4. sdk build and return IPFS of DNP_CORE to be installed

    dappnodesdk build
}

function new_iso() {

    INSTALLER_URL="https://github.com/dappnode/DAppNode_Installer.git"
    INSTALLER_DIR="DAppNode_Installer"

    ## 1. Which core packages to be updated?

    read -p "DAPPMANAGER will be updated? (Y/N)  " DAPPMANAGER_CONFIRM_BRANCH
    if [[ $DAPPMANAGER_CONFIRM_BRANCH == [yY] ]]
    then 
        read -p "which git tag?  " DAPPMANAGER_TAG
    fi

    read -p "BIND will be updated? (Y/N)  " BIND_CONFIRM_BRANCH
    if [[ $BIND_CONFIRM_BRANCH == [yY] ]]
    then 
        read -p "which git tag?  " BIND_TAG
    fi

    read -p "IPFS will be updated? (Y/N)  " IPFS_CONFIRM_BRANCH
    if [[ $IPFS_CONFIRM_BRANCH == [yY] ]]
    then 
        read -p "which git tag?  " IPFS_TAG
    fi

    read -p "VPN will be updated? (Y/N)  " VPN_CONFIRM_BRANCH
    if [[ $VPN_CONFIRM_BRANCH == [yY] ]]
    then 
        read -p "which git tag?  " VPN_TAG
    fi

    read -p "WIFI will be updated? (Y/N)  " WIFI_CONFIRM_BRANCH
    if [[ $WIFI_CONFIRM_BRANCH == [yY] ]]
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

    if [ -v DAPPMANAGER_TAG ]
    then
        set_new_tag "DAPPMANAGER" "$DAPPMANAGER_TAG"
    fi 

    if [ -v BIND_TAG ]
    then
        set_new_tag "BIND" "$BIND_TAG"
    fi 

    if [ -v IPFS_TAG ]
    then
        set_new_tag "IPFS" "$IPFS_TAG"
    fi 

    if [ -v VPN_TAG ]
    then
        set_new_tag "VPN" "$VPN_TAG"
    fi 

    if [ -v WIFI_TAG ]
    then
        set_new_tag "WIFI" "$WIFI_TAG"
    fi 

    echo "Successfully changed core packages tags in .dappnode_profile"

    ## 3. Create ISO image

    docker-compose build --no-cache
    docker-compose up

    ## 4. Get ISO image and isolate it

    cp images/*amd64.iso ../
    cd ..
    #rm -rf "$INSTALLER_DIR"

    ## 5. Create VM with the ISO image

    MACHINENAME="TEST-ISO"

    #Create VM
    VBoxManage createvm --name $MACHINENAME --register --basefolder "$(pwd)"
    #Set memory and network
    VBoxManage modifyvm $MACHINENAME --ioapic on
    VBoxManage modifyvm $MACHINENAME --memory 1024 --vram 128
    VBoxManage modifyvm $MACHINENAME --nic1 nat
    #Create Disk and connect Debian Iso
    VBoxManage createmedium --filename "$(pwd)"/"$MACHINENAME"/"$MACHINENAME"_DISK.vdi --size 80000 --format VDI 
    VBoxManage storagectl $MACHINENAME --name SATA --add sata --controller IntelAhci       
    VBoxManage storageattach $MACHINENAME --storagectl SATA --port 0 --device 0 --type hdd --medium  "$(pwd)"/"$MACHINENAME"/"$MACHINENAME"_DISK.vdi 
    VBoxManage storagectl $MACHINENAME --name IDE --add ide --controller PIIX4
    VBoxManage storageattach $MACHINENAME --storagectl IDE --port 1 --device 0 --type dvddrive --medium "$(pwd)"/*amd64.iso
    VBoxManage modifyvm $MACHINENAME --boot1 dvd --boot2 disk --boot3 none --boot4 none 

    #Enable RDP
    VBoxManage modifyvm $MACHINENAME --vrde on
    VBoxManage modifyvm $MACHINENAME --vrdemulticon on --vrdeport 10001

    #Start the VM
    VBoxHeadless --startvm $MACHINENAME
}

function information() {
    printf "\e[1m1) Core-Update: \e[0mthis option will return an IPFS of the core package with the core packages updated in the manifest (previously asked) \n\n\e[1mRequirements:\n\e[0m- git\n- DAppNode connected\n- ipfs package running\n- Docker\n- dappnodeSDK\n- Core packages versions to be tested\n\n\e[1m2) New iso: \e[0mwill create a virtual machine in virtual box, with an ISO previously created based on the new core packages versions\n\n\e[1mRequirements:\n\e[0m- Virtual box\n- git\n- DAppNode connected\n- ipfs package running\n- Docker\n- dappnodeSDK\n- Core packages versions to be tested\n\n"
}


PS3='Please enter your choice: '
options=("Core Update" "Generate new ISO" "Information" "Exit")
select opt in "${options[@]}"
do
    case $opt in
        "Core Update")
            printf "you choose %s \n\n" "$opt"
            core_update
            ;;
        "Generate new ISO")
            printf "you choose %s \n\n" "$opt"
            new_iso
            ;;
        "Information")
            printf "you choose %s \n\n" "$opt"
            information
            ;;
        "Exit")
            break
            ;;
        *) echo "invalid option";;
    esac
done