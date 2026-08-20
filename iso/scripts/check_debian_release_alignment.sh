#!/bin/bash
set -euo pipefail

SCRIPTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ISO_DIR=$(cd "${SCRIPTS_DIR}/.." && pwd)

source "${ISO_DIR}/debian_release.conf"

case "${DEBIAN_SUITE}" in
    bullseye) suite_major_version="11" ;;
    bookworm) suite_major_version="12" ;;
    trixie) suite_major_version="13" ;;
    forky) suite_major_version="14" ;;
    *)
        echo "[ERROR] Unknown Debian suite: ${DEBIAN_SUITE}"
        exit 1
        ;;
esac

if [ "${suite_major_version}" != "${DEBIAN_MAJOR_VERSION}" ]; then
    echo "[ERROR] Debian suite ${DEBIAN_SUITE} is Debian ${suite_major_version}, not Debian ${DEBIAN_MAJOR_VERSION}"
    exit 1
fi

generator="${SCRIPTS_DIR}/generate_dappnode_iso_debian.sh"
base_iso_name=$(sed -n 's/^BASE_ISO_NAME="\([^"]*\)"$/\1/p' "${generator}")

if [[ ! "${base_iso_name}" =~ ^debian-([0-9]+)\. ]]; then
    echo "[ERROR] Could not determine the Debian major version from BASE_ISO_NAME=${base_iso_name}"
    exit 1
fi

iso_major_version="${BASH_REMATCH[1]}"
if [ "${iso_major_version}" != "${DEBIAN_MAJOR_VERSION}" ]; then
    echo "[ERROR] Base ISO ${base_iso_name} is Debian ${iso_major_version}, but debian_release.conf expects Debian ${DEBIAN_MAJOR_VERSION} (${DEBIAN_SUITE})"
    exit 1
fi

expected_repository="d-i apt-setup/local0/repository string http://deb.debian.org/debian/ @DEBIAN_SUITE@ main contrib non-free-firmware"
preseed_files=(
    "${ISO_DIR}/preseeds/preseed.cfg"
    "${ISO_DIR}/preseeds/preseed_unattended.cfg"
)

for preseed_file in "${preseed_files[@]}"; do
    repository_count=$(grep -Ec '^d-i apt-setup/local[0-9]+/repository string ' "${preseed_file}" || true)
    if [ "${repository_count}" -ne 1 ]; then
        echo "[ERROR] Expected exactly one additional Debian repository in ${preseed_file}, found ${repository_count}"
        exit 1
    fi

    if ! grep -Fqx "${expected_repository}" "${preseed_file}"; then
        echo "[ERROR] Debian repository in ${preseed_file} must use the @DEBIAN_SUITE@ placeholder"
        exit 1
    fi
done

echo "[INFO] Debian release alignment is valid: Debian ${DEBIAN_MAJOR_VERSION} (${DEBIAN_SUITE}), ${base_iso_name}"
