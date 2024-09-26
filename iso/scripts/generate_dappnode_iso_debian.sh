#!/bin/bash
set -e

# Source = https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso
ISO_NAME=debian-12.7.0-amd64-netinst.iso
ISO_PATH="/images/${ISO_NAME}"
ISO_URL=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/
SHASUM="8fde79cfc6b20a696200fc5c15219cf6d721e8feb367e9e0e33a79d1cb68fa83  ${ISO_PATH}"

echo "Downloading debian ISO image: ${ISO_NAME}..."
if [ ! -f ${ISO_PATH} ]; then
    wget ${ISO_URL}/${ISO_NAME} \
        -O ${ISO_PATH}
fi
echo "Done!"

echo "Verifying download..."
[[ "$(shasum -a 256 ${ISO_PATH})" != "$SHASUM" ]] && {
    echo "ERROR: wrong shasum"
    exit 1
}

echo "Clean old files..."
rm -rf dappnode-isoº
rm -rf DappNode-debian-*

echo "Extracting the iso..."
xorriso -osirrox on -indev /images/${ISO_NAME} \
    -extract / dappnode-iso

echo "Obtaining the isohdpfx.bin for hybrid ISO..."
dd if=/images/${ISO_NAME} bs=432 count=1 \
    of=dappnode-iso/isolinux/isohdpfx.bin

cd /usr/src/app/dappnode-iso # /usr/src/app/dappnode-iso

echo "Downloading third-party packages..."
sed '1,/^\#\!ISOBUILD/!d' /usr/src/app/scripts/dappnode_install_pre.sh >/tmp/vars.sh
# shellcheck disable=SC1091
source /tmp/vars.sh

echo "Creating necessary directories and copying files..."
mkdir -p /usr/src/app/dappnode-iso/dappnode
cp -r /usr/src/app/scripts /usr/src/app/dappnode-iso/dappnode
cp -r /usr/src/app/dappnode/* /usr/src/app/dappnode-iso/dappnode

echo "Customizing preseed..."
mkdir -p /tmp/makeinitrd
cd install.amd
cp initrd.gz /tmp/makeinitrd/
if [[ $UNATTENDED == *"true"* ]]; then
    cp /usr/src/app/iso/preseeds/preseed_unattended.cfg /tmp/makeinitrd/preseed.cfg
else
    cp /usr/src/app/iso/preseeds/preseed.cfg /tmp/makeinitrd/preseed.cfg
fi
cd /tmp/makeinitrd
gunzip initrd.gz
cpio -id -H newc <initrd
# shellcheck disable=SC2002
cat initrd | cpio -t >/tmp/list
echo "preseed.cfg" >>/tmp/list
rm initrd
cpio -o -H newc </tmp/list >initrd
gzip initrd
cd -
mv /tmp/makeinitrd/initrd.gz ./initrd.gz
cd ..

echo "Configuring the boot menu for DappNode..."
cp /usr/src/app/iso/boot/grub.cfg boot/grub/grub.cfg
cp /usr/src/app/iso/boot/theme_1 boot/grub/theme/1
cp /usr/src/app/iso/boot/isolinux.cfg isolinux/isolinux.cfg
cp /usr/src/app/iso/boot/menu.cfg isolinux/menu.cfg
cp /usr/src/app/iso/boot/txt.cfg isolinux/txt.cfg
cp /usr/src/app/iso/boot/splash.png isolinux/splash.png

echo "Fix md5 sum..."
# shellcheck disable=SC2046
md5sum $(find ! -name "md5sum.txt" ! -path "./isolinux/*" -type f) >md5sum.txt

echo "Generating new iso..."
xorriso -as mkisofs -isohybrid-mbr isolinux/isohdpfx.bin \
    -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 \
    -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
    -isohybrid-gpt-basdat -o /images/DAppNode-debian-bookworm-amd64.iso .
