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
echo "Obtaining the isohdpfx.bin for hybrid ISO..."
dd if=/images/${BASE_ISO_NAME} bs=512 count=1 of=${ISO_BUILD_PATH}/boot/grub/isohdpfx.bin

echo "Creating the new Ubuntu ISO..."
mkisofs -isohybrid-mbr ${ISO_BUILD_PATH}/boot/grub/isohdpfx.bin \
    -eltorito-catalog ${ISO_BUILD_PATH}/boot.catalog \
    -eltorito-boot ${ISO_BUILD_PATH}/boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 \
    -boot-info-table -eltorito-alt-boot --efi-boot ${ISO_BUILD_PATH}/EFI/boot/bootx64.efi -no-emul-boot \
    -isohybrid-gpt-basdat -o ${DAPPNODE_ISO_NAME} .

exit 0

echo "Downloading third-party packages..."
sed '1,/^\#\!ISOBUILD/!d' ${DAPPNODE_SCRIPTS_PATH}/dappnode_install_pre.sh >${VARS_FILE}
# shellcheck disable=SC1091
source ${VARS_FILE}

echo "Creating necessary directories and copying files..."
mkdir -p ${ISO_BUILD_PATH}/dappnode
cp -r ${DAPPNODE_SCRIPTS_PATH} ${ISO_BUILD_PATH}/dappnode
cp -r /usr/src/app/dappnode/* ${ISO_BUILD_PATH}/dappnode

echo "Customizing preseed..."
mkdir -p ${TMP_INITRD}
cp ${ISO_BUILD_PATH}/casper/initrd ${TMP_INITRD}/
if [[ $UNATTENDED == *"true"* ]]; then
    # TODO: Check if this is the correct preseed file for Ubuntu
    cp /usr/src/app/iso/preseeds/preseed_unattended.cfg ${TMP_INITRD}/preseed.cfg
else
    cp /usr/src/app/iso/preseeds/preseed.cfg ${TMP_INITRD}/preseed.cfg
fi

cpio -id -H newc <${TMP_INITRD}/initrd
# shellcheck disable=SC2002
cat ${TMP_INITRD}/initrd | cpio -t >/tmp/list
echo "preseed.cfg" >>/tmp/list
rm ${TMP_INITRD}/initrd
cpio -o -H newc </tmp/list >initrd
#gzip initrd
cd -
mv ${TMP_INITRD}/initrd ${ISO_BUILD_PATH}/casper/initrd
cd ..

#mkdir -p boot/grub/theme

echo "Configuring the boot menu for DappNode..."
cp /usr/src/app/iso/boot/grub.cfg boot/grub/grub.cfg
#cp /usr/src/app/iso/boot/theme_1 boot/grub/theme/1
#cp /usr/src/app/iso/boot/isolinux.cfg isolinux/isolinux.cfg
#cp /usr/src/app/iso/boot/menu.cfg isolinux/menu.cfg
#cp /usr/src/app/iso/boot/txt.cfg isolinux/txt.cfg
#cp /usr/src/app/iso/boot/splash.png isolinux/splash.png

echo "Fix md5 sum..."
# shellcheck disable=SC2046
md5sum $(find . ! -name "md5sum.txt" -type f) >md5sum.txt

echo "Generating new iso..."
# Adjust paths as necessary based on actual directory contents
xorriso -as mkisofs \
    -isohybrid-mbr boot/grub/isohdpfx.bin \
    -b EFI/boot/grubx64.efi \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o /images/DAppNode-${ISO_NAME} \
    . #    -c boot/grub/boot.cat \
