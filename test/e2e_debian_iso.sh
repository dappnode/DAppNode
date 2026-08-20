#!/bin/bash
set -Eeuo pipefail

usage() {
    echo "Usage: $0 <Dappnode Debian unattended ISO>"
}

if [ "$#" -ne 1 ]; then
    usage
    exit 2
fi

ISO_PATH=$(realpath "$1")
if [ ! -f "${ISO_PATH}" ]; then
    echo "[ERROR] ISO not found: ${ISO_PATH}"
    exit 1
fi

required_commands=(qemu-img qemu-system-x86_64 xorriso ssh sshpass)
for command_name in "${required_commands[@]}"; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "[ERROR] Missing required command: ${command_name}"
        exit 1
    fi
done

OUTPUT_DIR=${E2E_OUTPUT_DIR:-"${PWD}/test-output/debian-e2e"}
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR=$(realpath "${OUTPUT_DIR}")

TEMP_ROOT=${RUNNER_TEMP:-/tmp}
VM_DIR=$(mktemp -d "${TEMP_ROOT%/}/dappnode-debian-e2e.XXXXXX")
DISK_PATH="${VM_DIR}/debian.qcow2"
KERNEL_PATH="${VM_DIR}/vmlinuz"
INITRD_PATH="${VM_DIR}/initrd.gz"
INSTALLER_SERIAL_LOG="${OUTPUT_DIR}/installer-serial.log"
INSTALLER_PROCESS_LOG="${OUTPUT_DIR}/installer-qemu.log"
SYSTEM_SERIAL_LOG="${OUTPUT_DIR}/installed-system-serial.log"
SYSTEM_PROCESS_LOG="${OUTPUT_DIR}/installed-system-qemu.log"
INSTALLED_SYSTEM_REPORT="${OUTPUT_DIR}/installed-system-report.log"

VM_DISK_SIZE=${E2E_VM_DISK_SIZE:-32G}
VM_MEMORY_MB=${E2E_VM_MEMORY_MB:-4096}
VM_CPUS=${E2E_VM_CPUS:-2}
INSTALL_TIMEOUT_SECONDS=${E2E_INSTALL_TIMEOUT_SECONDS:-3600}
BOOT_TIMEOUT_SECONDS=${E2E_BOOT_TIMEOUT_SECONDS:-600}
SSH_PORT=${E2E_SSH_PORT:-2222}
SSH_PASSWORD=${E2E_SSH_PASSWORD:-dappnode.s0}
qemu_pid=""

cleanup() {
    exit_code=$?
    trap - EXIT INT TERM

    if [ -n "${qemu_pid}" ] && kill -0 "${qemu_pid}" 2>/dev/null; then
        kill "${qemu_pid}" 2>/dev/null || true
        wait "${qemu_pid}" 2>/dev/null || true
    fi

    if [ "${KEEP_E2E_VM:-false}" = "true" ]; then
        echo "[INFO] Keeping VM files in ${VM_DIR}"
    else
        case "${VM_DIR}" in
            "${TEMP_ROOT%/}"/dappnode-debian-e2e.*) rm -rf -- "${VM_DIR}" ;;
            *) echo "[WARN] Refusing to remove unexpected VM directory: ${VM_DIR}" ;;
        esac
    fi

    exit "${exit_code}"
}
trap cleanup EXIT INT TERM

show_failure_logs() {
    echo "[INFO] Last installer serial output:"
    tail -n 200 "${INSTALLER_SERIAL_LOG}" 2>/dev/null || true
    echo "[INFO] Last installed-system serial output:"
    tail -n 200 "${SYSTEM_SERIAL_LOG}" 2>/dev/null || true
    echo "[INFO] QEMU process output:"
    tail -n 100 "${INSTALLER_PROCESS_LOG}" 2>/dev/null || true
    tail -n 100 "${SYSTEM_PROCESS_LOG}" 2>/dev/null || true
}

wait_for_process_exit() {
    process_id=$1
    timeout_seconds=$2
    description=$3
    deadline=$((SECONDS + timeout_seconds))

    while kill -0 "${process_id}" 2>/dev/null; do
        if [ "${SECONDS}" -ge "${deadline}" ]; then
            echo "[ERROR] Timed out waiting for ${description}"
            return 1
        fi
        sleep 10
    done

    wait "${process_id}"
}

qemu_acceleration=(-accel "tcg,thread=multi")
if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    qemu_acceleration=(-accel kvm -cpu host)
    echo "[INFO] Using KVM acceleration"
else
    echo "[WARN] /dev/kvm is unavailable; using slower TCG emulation"
fi

echo "[INFO] Extracting the Debian installer kernel and initrd from ${ISO_PATH}"
xorriso -osirrox on -indev "${ISO_PATH}" -extract /install.amd/vmlinuz "${KERNEL_PATH}" >/dev/null 2>&1
xorriso -osirrox on -indev "${ISO_PATH}" -extract /install.amd/initrd.gz "${INITRD_PATH}" >/dev/null 2>&1

echo "[INFO] Creating ${VM_DISK_SIZE} virtual installation disk"
qemu-img create -q -f qcow2 "${DISK_PATH}" "${VM_DISK_SIZE}"

echo "[INFO] Booting the unattended installer"
qemu-system-x86_64 \
    "${qemu_acceleration[@]}" \
    -m "${VM_MEMORY_MB}" \
    -smp "${VM_CPUS}" \
    -drive "file=${DISK_PATH},format=qcow2,if=virtio" \
    -cdrom "${ISO_PATH}" \
    -kernel "${KERNEL_PATH}" \
    -initrd "${INITRD_PATH}" \
    -append "auto=true priority=critical console=ttyS0,115200n8 --- quiet" \
    -nic user,model=virtio-net-pci \
    -display none \
    -monitor none \
    -serial "file:${INSTALLER_SERIAL_LOG}" \
    -no-reboot \
    >"${INSTALLER_PROCESS_LOG}" 2>&1 &
qemu_pid=$!

if ! wait_for_process_exit "${qemu_pid}" "${INSTALL_TIMEOUT_SECONDS}" "the Debian installer to complete"; then
    show_failure_logs
    exit 1
fi
qemu_pid=""

echo "[INFO] Installer completed; booting the installed virtual disk"
qemu-system-x86_64 \
    "${qemu_acceleration[@]}" \
    -m "${VM_MEMORY_MB}" \
    -smp "${VM_CPUS}" \
    -drive "file=${DISK_PATH},format=qcow2,if=virtio" \
    -boot order=c \
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
    -display none \
    -monitor none \
    -serial "file:${SYSTEM_SERIAL_LOG}" \
    >"${SYSTEM_PROCESS_LOG}" 2>&1 &
qemu_pid=$!

ssh_options=(
    -p "${SSH_PORT}"
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o ConnectionAttempts=1
    -o LogLevel=ERROR
)

ssh_guest() {
    SSHPASS="${SSH_PASSWORD}" sshpass -e ssh "${ssh_options[@]}" dappnode@127.0.0.1 "$@"
}

echo "[INFO] Waiting for SSH on the installed system"
boot_deadline=$((SECONDS + BOOT_TIMEOUT_SECONDS))
while ! ssh_guest true >/dev/null 2>&1; do
    if ! kill -0 "${qemu_pid}" 2>/dev/null; then
        echo "[ERROR] Installed-system VM exited before SSH became available"
        show_failure_logs
        exit 1
    fi
    if [ "${SECONDS}" -ge "${boot_deadline}" ]; then
        echo "[ERROR] Timed out waiting for SSH on the installed system"
        show_failure_logs
        exit 1
    fi
    sleep 10
done

echo "[INFO] Validating the installed Debian and DAppNode system"
ssh_guest bash -s <<'REMOTE_CHECKS' | tee "${INSTALLED_SYSTEM_REPORT}"
set -euo pipefail

source /etc/os-release
if [ "${ID}" != "debian" ] || [ "${VERSION_ID}" != "13" ] || [ "${VERSION_CODENAME}" != "trixie" ]; then
    echo "[ERROR] Expected Debian 13 (trixie), found ${PRETTY_NAME}"
    exit 1
fi

if grep -R -H -E --include='*.list' --include='*.sources' \
    '(^|[[:space:]])bookworm([[:space:]]|$)' /etc/apt 2>/dev/null; then
    echo "[ERROR] Found a Bookworm APT source on the installed system"
    exit 1
fi

dpkg_audit=$(dpkg --audit)
if [ -n "${dpkg_audit}" ]; then
    echo "[ERROR] dpkg reports incomplete or broken packages:"
    echo "${dpkg_audit}"
    exit 1
fi

package_version() {
    dpkg-query -W -f='${Version}' "$1"
}

tasksel_version=$(package_version tasksel)
task_english_version=$(package_version task-english)
debconf_version=$(package_version debconf)
python_debconf_version=$(package_version python3-debconf)

if [ "${tasksel_version}" != "${task_english_version}" ]; then
    echo "[ERROR] tasksel (${tasksel_version}) and task-english (${task_english_version}) do not match"
    exit 1
fi
if [ "${debconf_version}" != "${python_debconf_version}" ]; then
    echo "[ERROR] debconf (${debconf_version}) and python3-debconf (${python_debconf_version}) do not match"
    exit 1
fi

test -x /usr/src/dappnode/scripts/dappnode_install.sh
test -s /usr/src/dappnode/logs/iso_install.log
docker --version
docker compose version
docker info >/dev/null

echo "Installed OS: ${PRETTY_NAME}"
echo "tasksel family: ${tasksel_version}"
echo "debconf family: ${debconf_version}"
echo "[INFO] End-to-end Debian ISO installation checks passed"
REMOTE_CHECKS

echo "[INFO] Complete Debian ISO installation succeeded"
