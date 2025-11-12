# Versions
|  Package  | Version  |
|---|---|
bind.dnp.dappnode.eth|$BIND|
|ipfs.dnp.dappnode.eth|$IPFS|
|vpn.dnp.dappnode.eth |$VPN|
|dappmanager.dnp.dappnode.eth|$DAPPMANAGER|
|wifi.dnp.dappnode.eth|$WIFI|
|https.dnp.dappnode.eth|$HTTPS|
|wireguard.dnp.dappnode.eth|$WIREGUARD|
# Changes
Changes implemented in release $CORE
# Debian Attended version
Install and customize DAppNode using the attended ISO: **DAppNode-$CORE-debian-bookworm-amd64.iso**

## ISO SHA-256 Checksum
```
shasum -a 256 DAppNode-$CORE-debian-bookworm-amd64.iso
$SHASUM_DEBIAN_ATTENDED
```
# Debian Unattended version
Install DAppNode easily using the unattended ISO: **DAppNode-$CORE-debian-bookworm-amd64-unattended.iso**
Do a reboot right after the installation
:warning: **Warning**: This ISO will install Dappnode automatically, deleting all existing partitions on the disk

## ISO SHA-256 Checksum
```
shasum -a 256 DAppNode-$CORE-debian-bookworm-amd64-unattended.iso
$SHASUM_DEBIAN_UNATTENDED
```
# Ubuntu Unattended version
Install DAppNode easily using the unattended ISO: **DAppNode-$CORE-ubuntu-bookworm-amd64-unattended.iso**

## ISO SHA-256 Checksum
```
shasum -a 256 DAppNode-$CORE-ubuntu-bookworm-amd64-unattended.iso
$SHASUM_UBUNTU_UNATTENDED
```
Uploaded at https://ubuntu.iso.dappnode.io