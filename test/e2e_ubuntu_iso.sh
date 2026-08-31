#!/bin/bash
# Runs the generated unattended Ubuntu ISO through the complete UEFI USB test.
# It adds Ubuntu release and repository checks to the shared harness.
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

source "${SCRIPT_DIR}/e2e_iso_install.sh"
run_e2e_iso_install "$@"
