#!/bin/bash
set -e

SCRIPTS_DIR=$(dirname "${BASH_SOURCE[0]}")

source ${SCRIPTS_DIR}/common_iso_generation.sh

# Source = https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso
BASE_ISO_NAME="debian-12.7.0-amd64-netinst.iso"
BASE_ISO_PATH="/images/${BASE_ISO_NAME}"
BASE_ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/${BASE_ISO_NAME}"
BASE_ISO_SHASUM="8fde79cfc6b20a696200fc5c15219cf6d721e8feb367e9e0e33a79d1cb68fa83  ${BASE_ISO_PATH}"

DAPPNODE_ISO_NAME="${DAPPNODE_ISO_PREFIX}${BASE_ISO_NAME}"
DAPPNODE_ISO_PATH="/images/${DAPPNODE_ISO_NAME}"

customize_debian_preseed() {
    local iso_build_path=$1
    local workdir=$2

    echo "[INFO] Customizing preseed..."

    local tmp_initrd="/tmp/makeinitrd"
    local install_dir="${iso_build_path}/install.amd"
    local preseeds_dir="${workdir}/iso/preseeds"

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
    local iso_build_path=$1
    local workdir=$2

    local boot_dir="${workdir}/iso/boot"

    echo "[INFO] Configuring the boot menu for Dappnode..."
    cp ${boot_dir}/grub.cfg ${iso_build_path}/boot/grub/grub.cfg
    cp ${boot_dir}/theme_1 ${iso_build_path}/boot/grub/theme/1
    cp ${boot_dir}/isolinux.cfg ${iso_build_path}/isolinux/isolinux.cfg
    cp ${boot_dir}/menu.cfg ${iso_build_path}/isolinux/menu.cfg
    cp ${boot_dir}/txt.cfg ${iso_build_path}/isolinux/txt.cfg
    cp ${boot_dir}/splash.png ${iso_build_path}/isolinux/splash.png
}

generate_debian_iso() {
    local mbr_path=$1
    local iso_output_path=$2
    local iso_build_path=$3

    echo "[INFO] Generating new ISO..."

    xorriso -as mkisofs -isohybrid-mbr ${mbr_path} \
        -c /isolinux/boot.cat -b /isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 \
        -boot-info-table -eltorito-alt-boot -e /boot/grub/efi.img -no-emul-boot \
        -isohybrid-gpt-basdat -o "${iso_output_path}" ${iso_build_path}
}

download_iso "${BASE_ISO_PATH}" "${BASE_ISO_NAME}" "${BASE_ISO_URL}"
verify_download "${BASE_ISO_PATH}" "${BASE_ISO_SHASUM}"
clean_old_files "${ISO_BUILD_PATH}" "${DAPPNODE_ISO_PREFIX}"
extract_iso "${BASE_ISO_PATH}" "${ISO_BUILD_PATH}"
prepare_boot_process "${BASE_ISO_PATH}" "${ISO_BUILD_PATH}/isolinux/isohdpfx.bin"
add_dappnode_files_to_iso_build "${ISO_BUILD_PATH}" "${WORKDIR}"
customize_debian_preseed "${ISO_BUILD_PATH}" "${WORKDIR}"
configure_boot_menu "${ISO_BUILD_PATH}" "${WORKDIR}"
handle_checksums # TODO: Check if it fits both ubuntu and debian
generate_debian_iso "${ISO_BUILD_PATH}/isolinux/isohdpfx.bin" "${DAPPNODE_ISO_PATH}" "${ISO_BUILD_PATH}"
