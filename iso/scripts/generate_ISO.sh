#!/bin/sh
set -e

dockerd &
sleep 5

if [ "$CLEAN" = true ]; then
    rm -f /images/*.tar.xz
    rm -f /images/*.yml
    rm -f /images/*.json
    rm -f /images/*.txz
fi

if [ "$BUILD" = true ]; then
    /usr/src/app/iso/scripts/generate_docker_images.sh
else
    /usr/src/app/iso/scripts/download_core.sh
fi

#file generated to detectd ISO installation
mkdir -p /usr/src/app/dappnode
touch /usr/src/app/dappnode/iso_install.log

/usr/src/app/iso/scripts/generate_dappnode_iso_debian.sh
