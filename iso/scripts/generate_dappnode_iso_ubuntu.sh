#!/bin/bash
set -e

ISO_BUILD_PATH="/usr/src/app/dappnode-iso"
DAPPNODE_SCRIPTS_PATH="/usr/src/app/scripts"
VARS_FILE="/tmp/vars.sh"
TMP_INITRD="/tmp/makeinitrd"

# Source = https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso
BASE_ISO_NAME=ubuntu-24.04-live-server-amd64.iso
BASE_ISO_PATH="/images/${BASE_ISO_NAME}"
DAPPNODE_ISO_PATH="/images/DAppNode-${BASE_ISO_NAME}"
ISO_URL=https://labs.eif.urjc.es/mirror/ubuntu-releases/24.04/
SHASUM="8762f7e74e4d64d72fceb5f70682e6b069932deedb4949c6975d0f0fe0a91be3  ${BASE_ISO_PATH}"

echo "Downloading Ubuntu ISO image: ${BASE_ISO_NAME}..."
if [ ! -f ${BASE_ISO_PATH} ]; then
    wget ${ISO_URL}/${BASE_ISO_NAME} \
        -O ${BASE_ISO_PATH}
fi
echo "Done!"

echo "Verifying download..."
[[ "$(shasum -a 256 ${BASE_ISO_PATH})" != "$SHASUM" ]] && {
    echo "ERROR: wrong shasum"
    exit 1
}

echo "Clean old files..."
rm -rf dappnode-isoº
rm -rf DappNode-ubuntu-*

echo "Extracting the iso..."
osirrox -indev ${BASE_ISO_PATH} -extract / dappnode-iso

# Using a 512-byte block size to ensure the entire Master Boot Record (MBR) is captured.
# The MBR contains boot code, the partition table, and a boot signature, all essential for creating bootable media.
echo "Obtaining the MBR for hybrid ISO..."
dd if=${BASE_ISO_PATH} bs=512 count=1 of=${ISO_BUILD_PATH}/mbr

efi_start=$(fdisk -l ${BASE_ISO_PATH} | grep 'Appended2' | awk '{print $2}')
efi_end=$(fdisk -l ${BASE_ISO_PATH} | grep 'Appended2' | awk '{print $3}')
efi_size=$(expr ${efi_end} - ${efi_start} + 1)
echo "Obtaining the EFI partition image from ${efi_start} with size ${efi_size}..."
dd if=${BASE_ISO_PATH} bs=512 skip="$efi_start" count="$efi_size" of=${ISO_BUILD_PATH}/efi

echo "Downloading third-party packages..."
sed '1,/^\#\!ISOBUILD/!d' ${DAPPNODE_SCRIPTS_PATH}/dappnode_install_pre.sh >${VARS_FILE}
# shellcheck disable=SC1091
source ${VARS_FILE}

echo "Creating necessary directories and copying files..."
mkdir -p ${ISO_BUILD_PATH}/dappnode
cp -r ${DAPPNODE_SCRIPTS_PATH} ${ISO_BUILD_PATH}/dappnode
cp -r /usr/src/app/dappnode/* ${ISO_BUILD_PATH}/dappnode

echo "Adding preseed..."
if [[ $UNATTENDED == *"true"* ]]; then
    cp /usr/src/app/iso/preseeds//ubuntu/autoinstall_unattended.yaml ${ISO_BUILD_PATH}/autoinstall.yaml
else
    cp /usr/src/app/iso/preseeds/ubuntu/autoinstall.yaml ${ISO_BUILD_PATH}/autoinstall.yaml
fi

#mkdir -p boot/grub/theme

echo "Configuring the boot menu for DappNode..."
cp /usr/src/app/iso/boot/ubuntu/grub.cfg ${ISO_BUILD_PATH}/boot/grub/grub.cfg
#cp /usr/src/app/iso/boot/theme_1 boot/grub/theme/1
#cp /usr/src/app/iso/boot/isolinux.cfg isolinux/isolinux.cfg
#cp /usr/src/app/iso/boot/menu.cfg isolinux/menu.cfg
#cp /usr/src/app/iso/boot/txt.cfg isolinux/txt.cfg
#cp /usr/src/app/iso/boot/splash.png isolinux/splash.png

# TODO: Is this necessary? How to do it?
echo "Fix md5 sum..."
# shellcheck disable=SC2046
md5sum $(find . ! -name "md5sum.txt" -type f) >md5sum.txt

echo "Creating the new Ubuntu ISO..."
mkisofs \
    -rational-rock -joliet -joliet-long -full-iso9660-filenames \
    -iso-level 3 -partition_offset 16 --grub2-mbr ${ISO_BUILD_PATH}/mbr \
    --mbr-force-bootable -append_partition 2 0xEF ${ISO_BUILD_PATH}/efi \
    -appended_part_as_gpt \
    -eltorito-catalog /boot.catalog \
    -eltorito-boot /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 \
    -boot-info-table --grub2-boot-info -eltorito-alt-boot --efi-boot '--interval:appended_partition_2:all::' -no-emul-boot \
    -o ${DAPPNODE_ISO_PATH} ${ISO_BUILD_PATH}
