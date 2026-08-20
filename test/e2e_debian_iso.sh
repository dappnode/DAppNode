#!/bin/bash
# Configures the shared ISO installation harness for Debian's installer layout.
# The Debian end-to-end workflow calls this wrapper with its unattended ISO.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

source "${REPO_ROOT}/iso/debian_release.conf"

E2E_DISTRO="debian"
E2E_EXPECTED_ID="debian"
E2E_EXPECTED_VERSION="${DEBIAN_MAJOR_VERSION}"
E2E_EXPECTED_CODENAME="${DEBIAN_SUITE}"
E2E_KERNEL_ISO_PATH="/install.amd/vmlinuz"
E2E_INITRD_ISO_PATH="/install.amd/initrd.gz"
E2E_KERNEL_ARGS="auto=true priority=critical console=ttyS0,115200n8 --- quiet"

source "${SCRIPT_DIR}/e2e_iso_install.sh"
run_e2e_iso_install "$@"
