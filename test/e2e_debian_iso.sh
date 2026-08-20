#!/bin/bash
# Runs the generated unattended Debian ISO through the complete UEFI USB test.
# It adds Debian release and package-alignment checks to the shared harness.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

source "${REPO_ROOT}/iso/debian_release.conf"

E2E_DISTRO="debian"
E2E_EXPECTED_ID="debian"
E2E_EXPECTED_VERSION="${DEBIAN_MAJOR_VERSION}"
E2E_EXPECTED_CODENAME="${DEBIAN_SUITE}"

source "${SCRIPT_DIR}/e2e_iso_install.sh"
run_e2e_iso_install "$@"
