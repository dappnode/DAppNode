#!/bin/bash
set -e

SCRIPTS_DIR=$(dirname "${BASH_SOURCE[0]}")

source ${SCRIPTS_DIR}/common_iso_generation.sh

BASE_ISO_NAME=ubuntu-24.04-live-server-amd64.iso
BASE_ISO_PATH="/images/${BASE_ISO_NAME}"
BASE_ISO_URL="https://labs.eif.urjc.es/mirror/ubuntu-releases/24.04/${BASE_ISO_NAME}"
BASE_ISO_SHASUM="8762f7e74e4d64d72fceb5f70682e6b069932deedb4949c6975d0f0fe0a91be3  ${BASE_ISO_PATH}"

DAPPNODE_ISO_NAME="${DAPPNODE_ISO_PREFIX}${BASE_ISO_NAME}"
DAPPNODE_ISO_PATH="/images/${DAPPNODE_ISO_NAME}"

get_efi_partition() {
    local base_iso_path=$1
    local dest_efi_path=$2
    local block_size=512

    local efi_start=$(fdisk -l ${base_iso_path} | grep 'Appended2' | awk '{print $2}')
    local efi_end=$(fdisk -l ${base_iso_path} | grep 'Appended2' | awk '{print $3}')
    local efi_size=$(expr ${efi_end} - ${efi_start} + 1)

    echo "[INFO] Obtaining the EFI partition image from ${efi_start} with size ${efi_size}..."
    dd if=${base_iso_path} bs=${block_size} skip="$efi_start" count="$efi_size" of=${dest_efi_path}
}

add_ubuntu_autoinstall() {
    local preseeds_dir=$1
    local iso_build_path=$2

    echo "[INFO] Adding preseed..."
    if [[ $UNATTENDED == *"true"* ]]; then
        cp ${preseeds_dir}/autoinstall_unattended.yaml ${iso_build_path}/autoinstall.yaml
    else
        cp ${preseeds_dir}/autoinstall.yaml ${iso_build_path}/autoinstall.yaml
    fi
}

configure_boot_menu() {
    echo "[INFO] Configuring the boot menu for Dappnode..."
    cp -r /usr/src/app/iso/boot/ubuntu/* ${ISO_BUILD_PATH}/boot/grub/
}

generate_ubuntu_iso() {
    local mbr_path=$1
    local efi_path=$2
    local iso_output_path=$3
    local iso_build_path=$4

    echo "[INFO] Creating the new Ubuntu ISO..."
    mkisofs \
        -rational-rock -joliet -joliet-long -full-iso9660-filenames \
        -iso-level 3 -partition_offset 16 --grub2-mbr ${mbr_path} \
        --mbr-force-bootable -append_partition 2 0xEF ${efi_path} \
        -appended_part_as_gpt \
        -eltorito-catalog /boot.catalog \
        -eltorito-boot /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 \
        -boot-info-table --grub2-boot-info -eltorito-alt-boot --efi-boot '--interval:appended_partition_2:all::' -no-emul-boot \
        -o ${iso_output_path} ${iso_build_path}
}

download_iso "${BASE_ISO_PATH}" "${BASE_ISO_NAME}" "${BASE_ISO_URL}"
verify_download "${BASE_ISO_PATH}" "${BASE_ISO_SHASUM}"
clean_old_files "${ISO_BUILD_PATH}" "${DAPPNODE_ISO_PREFIX}"
extract_iso "${BASE_ISO_PATH}" "${ISO_BUILD_PATH}"
prepare_boot_process "${BASE_ISO_PATH}" "${ISO_BUILD_PATH}/mbr"
get_efi_partition "${BASE_ISO_PATH}" "${ISO_BUILD_PATH}/efi"
add_dappnode_files_to_iso_build "${ISO_BUILD_PATH}" "${WORKDIR}"
add_ubuntu_autoinstall "/usr/src/app/iso/preseeds/ubuntu" "${ISO_BUILD_PATH}"
configure_boot_menu
handle_checksums
generate_ubuntu_iso "${ISO_BUILD_PATH}/mbr" "${ISO_BUILD_PATH}/efi" "${DAPPNODE_ISO_PATH}" "${ISO_BUILD_PATH}"
