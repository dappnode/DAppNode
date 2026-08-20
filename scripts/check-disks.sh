#!/bin/sh
#
# This is run by d-i before the partman step (e.g. d-i partman/early_command)

USBDEV=$(list-devices usb-partition | sed "s/\(.*\)./\1/" | sort -u | head -1 );
if [ -z "${USBDEV}" ]; then
    DEVICE=$(list-devices disk)
else
    DEVICE=$(list-devices disk | grep -v "${USBDEV}")
fi
for DISK in ${DEVICE}; do
    DISKS="${DISKS} ${DISK}";
done;
DISKS=$(echo "${DISKS}" | sed "s/^ //g");
debconf-set partman-auto/disk "$DISKS";

# grub-installer/bootdev is preseeded to "default", which marks the question as
# already seen. grub-installer then resolves "default" to the first entry of
# grub-mkdevicemap, i.e. (hd0) -- the installer USB itself. Its safeguard against
# installing onto the installation media only runs for grub-pc, so on UEFI it
# happily targets the stick and then dies reading its partition table:
#   Can't read partition table from /dev/sda
# Point it at the same non-USB disks partman is using. grub-installer accepts a
# space separated list and installs to each entry in turn.
debconf-set grub-installer/bootdev "$DISKS";
