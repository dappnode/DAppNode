#!/bin/bash
# Runs the generated unattended Debian ISO through the complete UEFI USB test.
# It adds Debian release and package-alignment checks to the shared harness.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
GENERATOR="${REPO_ROOT}/iso/scripts/generate_dappnode_iso_debian.sh"
PRESEED="${REPO_ROOT}/iso/preseeds/preseed_unattended.cfg"

base_iso_name=$(sed -n 's/^BASE_ISO_NAME="\{0,1\}\([^"[:space:]]*\)"\{0,1\}$/\1/p' "${GENERATOR}")
if [[ ! "${base_iso_name}" =~ ^debian-([0-9]+)\. ]]; then
    echo "[ERROR] Could not determine the Debian release from BASE_ISO_NAME=${base_iso_name}"
    exit 1
fi
debian_major_version=${BASH_REMATCH[1]}

# The installed system must track the suite the preseed configures for APT.
debian_suite=$(sed -n 's|^d-i apt-setup/local0/repository string http://deb\.debian\.org/debian/ \([a-z]*\) .*|\1|p' "${PRESEED}")
if [ -z "${debian_suite}" ]; then
    echo "[ERROR] Could not determine the Debian suite from ${PRESEED}"
    exit 1
fi

E2E_DISTRO="debian"
E2E_EXPECTED_ID="debian"
E2E_EXPECTED_VERSION="${debian_major_version}"
E2E_EXPECTED_CODENAME="${debian_suite}"

source "${SCRIPT_DIR}/e2e_iso_install.sh"
run_e2e_iso_install "$@"
