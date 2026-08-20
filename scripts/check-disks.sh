#!/bin/sh
# Selects non-USB disks for Debian partitioning before the partman step.
# It gives GRUB the same targets so the installer USB is never selected.

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
debconf-set grub-installer/bootdev "$DISKS";
