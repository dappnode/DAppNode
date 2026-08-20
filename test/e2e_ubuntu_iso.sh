#!/bin/bash
# Configures the shared ISO installation harness for Ubuntu's autoinstall layout.
# The Ubuntu end-to-end workflow calls this wrapper with its unattended ISO.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
GENERATOR="${REPO_ROOT}/iso/scripts/generate_dappnode_iso_ubuntu.sh"

base_iso_name=$(sed -n 's/^BASE_ISO_NAME="\{0,1\}\([^"[:space:]]*\)"\{0,1\}$/\1/p' "${GENERATOR}")
if [[ ! "${base_iso_name}" =~ ^ubuntu-([0-9]+\.[0-9]+)(\.[0-9]+)?-live-server-amd64\.iso$ ]]; then
    echo "[ERROR] Could not determine the Ubuntu release from BASE_ISO_NAME=${base_iso_name}"
    exit 1
fi

E2E_DISTRO="ubuntu"
E2E_EXPECTED_ID="ubuntu"
E2E_EXPECTED_VERSION="${BASH_REMATCH[1]}"
E2E_EXPECTED_CODENAME="AUTO"
E2E_KERNEL_ISO_PATH="/casper/vmlinuz"
E2E_INITRD_ISO_PATH="/casper/initrd"
E2E_KERNEL_ARGS="autoinstall console=ttyS0,115200n8 --- quiet"

source "${SCRIPT_DIR}/e2e_iso_install.sh"
run_e2e_iso_install "$@"
