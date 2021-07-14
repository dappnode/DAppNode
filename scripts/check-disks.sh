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