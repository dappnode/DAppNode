#!/bin/bash

set -e

sed '1,/^\#\!ISOBUILD/!d' /usr/src/app/.dappnode_profile >/tmp/vars.sh
# shellcheck disable=SC1091
source /tmp/vars.sh

DAPPNODE_CORE_DIR="/images"
DAPPNODE_HASH_FILE="${DAPPNODE_CORE_DIR}/packages-content-hash.csv"
CONTENT_HASH_PKGS=(geth nethermind erigon prysm teku lighthouse nimbus)
IPFS_ENDPOINT=${IPFS_ENDPOINT:-"http://ipfs.io"}

SWGET="wget -q -O-"
WGET="wget"

components=(BIND IPFS WIREGUARD DAPPMANAGER WIFI HTTPS)

# The indirect variable expansion used in ${!ver##*:} allows us to use versions like 'dev:development'
# If such variable with 'dev:'' suffix is used, then the component is built from specified branch or commit.
for comp in "${components[@]}"; do
    ver="${comp}_VERSION"
    DOWNLOAD_URL="https://github.com/dappnode/DNP_${comp}/releases/download/v${!ver}"
    if [[ ${!ver} == /ipfs/* ]]; then
        DOWNLOAD_URL="${IPFS_ENDPOINT}/api/v0/cat?arg=${!ver%:*}"
    fi

    eval "${comp}_URL=\"${DOWNLOAD_URL}/${comp,,}.dnp.dappnode.eth_${!ver##*:}_linux-amd64.txz\""
    eval "${comp}_YML=\"${DOWNLOAD_URL}/docker-compose.yml\""
    eval "${comp}_MANIFEST=\"${DOWNLOAD_URL}/dappnode_package.json\""
    eval "${comp}_YML_FILE=\"${DAPPNODE_CORE_DIR}/docker-compose-${comp,,}.yml\""
    eval "${comp}_FILE=\"${DAPPNODE_CORE_DIR}/${comp,,}.dnp.dappnode.eth_${!ver##*:}_linux-amd64.txz\""
    eval "${comp}_MANIFEST_FILE=\"${DAPPNODE_CORE_DIR}/dappnode_package-${comp,,}.json\""
done

dappnode_core_download() {
    for comp in "${components[@]}"; do
        ver="${comp}_VERSION"
        if [[ ${!ver} != dev:* ]]; then
            # Download DAppNode Core Images if it's needed
            eval "[ -f \$${comp}_FILE ] || $WGET -O \$${comp}_FILE \$${comp}_URL"
            # Download DAppNode Core docker-compose yml files if it's needed
            eval "[ -f \$${comp}_YML_FILE ] || $WGET -O \$${comp}_YML_FILE \$${comp}_YML"
            # Download DAppNode Core manifest files if it's needed
            eval "[ -f \$${comp}_MANIFEST_FILE ] || $WGET -O \$${comp}_MANIFEST_FILE \$${comp}_MANIFEST"
        fi
    done
}

grabContentHashes() {
    rm -f $DAPPNODE_HASH_FILE
    for comp in "${CONTENT_HASH_PKGS[@]}"; do
        echo "Grabbing ${comp}"
        CONTENT_HASH=$(eval "${SWGET}" https://github.com/dappnode/DAppNodePackage-"${comp}"/releases/latest/download/content-hash)
        if [ -z "$CONTENT_HASH" ]; then
            echo "ERROR! Failed to find content hash of ${comp}."
            exit 1
        fi
        echo "${comp}.dnp.dappnode.eth,${CONTENT_HASH}" >>${DAPPNODE_HASH_FILE}
    done
}

echo -e "\e[32mDownloading DAppNode Core...\e[0m"
dappnode_core_download

echo -e "\e[32mGrabbing latest content hashes...\e[0m"
grabContentHashes

mkdir -p /usr/src/app/dappnode/DNCORE

echo -e "\e[32mCopying files...\e[0m"
cp /images/*.txz /usr/src/app/dappnode/DNCORE
cp /images/*.yml /usr/src/app/dappnode/DNCORE
cp /images/*.json /usr/src/app/dappnode/DNCORE
cp ${DAPPNODE_HASH_FILE} /usr/src/app/dappnode/DNCORE
cp /usr/src/app/.dappnode_profile /usr/src/app/dappnode/DNCORE
