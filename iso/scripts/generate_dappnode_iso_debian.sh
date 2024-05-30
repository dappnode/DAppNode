#!/bin/bash
set -e

source /usr/src/app/iso/scripts/common_functions.sh

# Source = https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso
BASE_ISO_NAME="debian-12.5.0-amd64-netinst.iso"
BASE_ISO_PATH="/images/${BASE_ISO_NAME}"
BASE_ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/${BASE_ISO_NAME}"
BASE_ISO_SHASUM="013f5b44670d81280b5b1bc02455842b250df2f0c6763398feb69af1a805a14f"

WORKDIR="/usr/src/app"
ISO_BUILD_PATH="${WORKDIR}/dappnode-iso"
DAPPNODE_ISO_PREFIX="Dappnode-"
DAPPNODE_ISO_NAME="${DAPPNODE_ISO_PREFIX}${BASE_ISO_NAME}"

download_third_party_packages() {
    echo "[INFO] Downloading third-party packages..."
    sed '1,/^\#\!ISOBUILD/!d' ${WORKDIR}/scripts/dappnode_install_pre.sh >/tmp/vars.sh
    # shellcheck disable=SC1091
    source /tmp/vars.sh
}

add_dappnode_files() {
    echo "[INFO] Creating necessary directories and copying files..."
    mkdir -p ${ISO_BUILD_PATH}/dappnode
    cp -r ${WORKDIR}/scripts ${ISO_BUILD_PATH}/dappnode
    cp -r ${WORKDIR}/dappnode/* ${ISO_BUILD_PATH}/dappnode
}

customize_debian_preseed() {
    echo "[INFO] Customizing preseed..."

    local tmp_initrd="/tmp/makeinitrd"
    local install_dir="${ISO_BUILD_PATH}/install.amd"
    local preseeds_dir="${WORKDIR}/iso/preseeds"

    rm -rf "${tmp_initrd}"
    mkdir -p "${tmp_initrd}"

    local preseed_name="preseed.cfg"
    [[ $UNATTENDED == *"true"* ]] && preseed_name="preseed_unattended.cfg"

    local preseed_file="${preseeds_dir}/${preseed_name}"

    if [ ! -f "${preseed_file}" ]; then
        echo "[ERROR] Preseed file not found: ${preseed_file}"
        exit 1
    fi

    # Extract the initrd into a temporary directory
    gunzip -c "${install_dir}/initrd.gz" | cpio -idum -D "${tmp_initrd}" || {
        echo "[ERROR] Could not decompress and extract initrd"
        exit 1
    }

    # Add the preseed file to the initrd
    cp "${preseed_file}" "${tmp_initrd}/preseed.cfg" || {
        echo "[ERROR] Could not copy preseed file"
        exit 1
    }

    # Recreate (and recompress) the initrd
    (cd "${tmp_initrd}" && find . -print0 | cpio -0 -ov -H newc | gzip >"${install_dir}/initrd.gz") || {
        echo "[ERROR] Could not create new initrd"
        exit 1
    }

    echo "[INFO] Preseed customization complete."
}

configure_boot_menu() {
    local boot_dir="${WORKDIR}/iso/boot"

    echo "[INFO] Configuring the boot menu for Dappnode..."
    cp ${boot_dir}/grub.cfg ${ISO_BUILD_PATH}/boot/grub/grub.cfg
    cp ${boot_dir}/theme_1 ${ISO_BUILD_PATH}/boot/grub/theme/1
    cp ${boot_dir}/isolinux.cfg ${ISO_BUILD_PATH}/isolinux/isolinux.cfg
    cp ${boot_dir}/menu.cfg ${ISO_BUILD_PATH}/isolinux/menu.cfg
    cp ${boot_dir}/txt.cfg ${ISO_BUILD_PATH}/isolinux/txt.cfg
    cp ${boot_dir}/splash.png ${ISO_BUILD_PATH}/isolinux/splash.png
}

generate_debian_iso() {

    echo "[INFO] Generating new ISO..."

    xorriso -as mkisofs -isohybrid-mbr ${ISO_BUILD_PATH}/isolinux/isohdpfx.bin \
        -c /isolinux/boot.cat -b /isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 \
        -boot-info-table -eltorito-alt-boot -e /boot/grub/efi.img -no-emul-boot \
        -isohybrid-gpt-basdat -o "/images/${DAPPNODE_ISO_NAME}" ${ISO_BUILD_PATH}
}

download_iso "${BASE_ISO_PATH}" "${BASE_ISO_NAME}" "${BASE_ISO_URL}"
verify_download "${BASE_ISO_PATH}" "${BASE_ISO_SHASUM}"
clean_old_files "${ISO_BUILD_PATH}" "${DAPPNODE_ISO_PREFIX}"
extract_iso "${BASE_ISO_PATH}" "${ISO_BUILD_PATH}"
prepare_boot_process "${BASE_ISO_PATH}" "${ISO_BUILD_PATH}/isolinux/isohdpfx.bin"
download_third_party_packages
add_dappnode_files
customize_debian_preseed
configure_boot_menu
handle_checksums # TODO: Check if it fits both ubuntu and debian
generate_debian_iso
