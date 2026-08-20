#!/bin/bash
# Shared QEMU harness that installs a DAppNode ISO onto a virtual disk.
# It boots the result and validates the OS, packages, Docker, and DAppNode files.
set -Eeuo pipefail

run_e2e_iso_install() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: $0 <Dappnode ${E2E_DISTRO} unattended ISO>"
        return 2
    fi

    local iso_path
    iso_path=$(realpath "$1")
    if [ ! -f "${iso_path}" ]; then
        echo "[ERROR] ISO not found: ${iso_path}"
        return 1
    fi

    local required_commands=(qemu-img qemu-system-x86_64 xorriso ssh sshpass)
    local command_name
    for command_name in "${required_commands[@]}"; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            echo "[ERROR] Missing required command: ${command_name}"
            return 1
        fi
    done

    local output_dir=${E2E_OUTPUT_DIR:-"${PWD}/test-output/${E2E_DISTRO}-e2e"}
    mkdir -p "${output_dir}"
    output_dir=$(realpath "${output_dir}")

    temp_root=${RUNNER_TEMP:-/tmp}
    vm_dir=$(mktemp -d "${temp_root%/}/dappnode-${E2E_DISTRO}-e2e.XXXXXX")
    local disk_path="${vm_dir}/${E2E_DISTRO}.qcow2"
    local kernel_path="${vm_dir}/vmlinuz"
    local initrd_path="${vm_dir}/initrd"
    local installer_serial_log="${output_dir}/installer-serial.log"
    local installer_process_log="${output_dir}/installer-qemu.log"
    local system_serial_log="${output_dir}/installed-system-serial.log"
    local system_process_log="${output_dir}/installed-system-qemu.log"
    local installed_system_report="${output_dir}/installed-system-report.log"

    local vm_disk_size=${E2E_VM_DISK_SIZE:-32G}
    local vm_memory_mb=${E2E_VM_MEMORY_MB:-4096}
    local vm_cpus=${E2E_VM_CPUS:-2}
    local install_timeout_seconds=${E2E_INSTALL_TIMEOUT_SECONDS:-3600}
    local boot_timeout_seconds=${E2E_BOOT_TIMEOUT_SECONDS:-600}
    local ssh_port=${E2E_SSH_PORT:-2222}
    local ssh_password=${E2E_SSH_PASSWORD:-dappnode.s0}
    qemu_pid=""

    cleanup_e2e_vm() {
        local exit_code=$?
        trap - EXIT INT TERM

        if [ -n "${qemu_pid}" ] && kill -0 "${qemu_pid}" 2>/dev/null; then
            kill "${qemu_pid}" 2>/dev/null || true
            wait "${qemu_pid}" 2>/dev/null || true
        fi

        if [ "${KEEP_E2E_VM:-false}" = "true" ]; then
            echo "[INFO] Keeping VM files in ${vm_dir}"
        else
            case "${vm_dir}" in
                "${temp_root%/}"/dappnode-"${E2E_DISTRO}"-e2e.*) rm -rf -- "${vm_dir}" ;;
                *) echo "[WARN] Refusing to remove unexpected VM directory: ${vm_dir}" ;;
            esac
        fi

        exit "${exit_code}"
    }
    trap cleanup_e2e_vm EXIT INT TERM

    show_failure_logs() {
        echo "[INFO] Last installer serial output:"
        tail -n 200 "${installer_serial_log}" 2>/dev/null || true
        echo "[INFO] Last installed-system serial output:"
        tail -n 200 "${system_serial_log}" 2>/dev/null || true
        echo "[INFO] QEMU process output:"
        tail -n 100 "${installer_process_log}" 2>/dev/null || true
        tail -n 100 "${system_process_log}" 2>/dev/null || true
    }

    wait_for_process_exit() {
        local process_id=$1
        local timeout_seconds=$2
        local description=$3
        local deadline=$((SECONDS + timeout_seconds))

        while kill -0 "${process_id}" 2>/dev/null; do
            if [ "${SECONDS}" -ge "${deadline}" ]; then
                echo "[ERROR] Timed out waiting for ${description}"
                return 1
            fi
            sleep 10
        done

        wait "${process_id}"
    }

    local qemu_acceleration=(-accel "tcg,thread=multi")
    if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        qemu_acceleration=(-accel kvm -cpu host)
        echo "[INFO] Using KVM acceleration"
    else
        echo "[WARN] /dev/kvm is unavailable; using slower TCG emulation"
    fi

    echo "[INFO] Extracting the ${E2E_DISTRO} installer kernel and initrd from ${iso_path}"
    xorriso -osirrox on -indev "${iso_path}" -extract "${E2E_KERNEL_ISO_PATH}" "${kernel_path}" >/dev/null 2>&1
    xorriso -osirrox on -indev "${iso_path}" -extract "${E2E_INITRD_ISO_PATH}" "${initrd_path}" >/dev/null 2>&1

    echo "[INFO] Creating ${vm_disk_size} virtual installation disk"
    qemu-img create -q -f qcow2 "${disk_path}" "${vm_disk_size}"

    echo "[INFO] Booting the unattended ${E2E_DISTRO} installer"
    qemu-system-x86_64 \
        "${qemu_acceleration[@]}" \
        -m "${vm_memory_mb}" \
        -smp "${vm_cpus}" \
        -drive "file=${disk_path},format=qcow2,if=virtio" \
        -cdrom "${iso_path}" \
        -kernel "${kernel_path}" \
        -initrd "${initrd_path}" \
        -append "${E2E_KERNEL_ARGS}" \
        -nic user,model=virtio-net-pci \
        -display none \
        -monitor none \
        -serial "file:${installer_serial_log}" \
        -no-reboot \
        >"${installer_process_log}" 2>&1 &
    qemu_pid=$!

    if ! wait_for_process_exit "${qemu_pid}" "${install_timeout_seconds}" "the ${E2E_DISTRO} installer to complete"; then
        show_failure_logs
        return 1
    fi
    qemu_pid=""

    echo "[INFO] Installer completed; booting the installed virtual disk"
    qemu-system-x86_64 \
        "${qemu_acceleration[@]}" \
        -m "${vm_memory_mb}" \
        -smp "${vm_cpus}" \
        -drive "file=${disk_path},format=qcow2,if=virtio" \
        -boot order=c \
        -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${ssh_port}-:22" \
        -display none \
        -monitor none \
        -serial "file:${system_serial_log}" \
        >"${system_process_log}" 2>&1 &
    qemu_pid=$!

    local ssh_options=(
        -p "${ssh_port}"
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o ConnectTimeout=5
        -o ConnectionAttempts=1
        -o LogLevel=ERROR
    )

    ssh_guest() {
        SSHPASS="${ssh_password}" sshpass -e ssh "${ssh_options[@]}" dappnode@127.0.0.1 "$@"
    }

    echo "[INFO] Waiting for SSH on the installed system"
    local boot_deadline=$((SECONDS + boot_timeout_seconds))
    while ! ssh_guest true >/dev/null 2>&1; do
        if ! kill -0 "${qemu_pid}" 2>/dev/null; then
            echo "[ERROR] Installed-system VM exited before SSH became available"
            show_failure_logs
            return 1
        fi
        if [ "${SECONDS}" -ge "${boot_deadline}" ]; then
            echo "[ERROR] Timed out waiting for SSH on the installed system"
            show_failure_logs
            return 1
        fi
        sleep 10
    done

    echo "[INFO] Validating the installed ${E2E_DISTRO} and DAppNode system"
    ssh_guest bash -s -- \
        "${E2E_DISTRO}" \
        "${E2E_EXPECTED_ID}" \
        "${E2E_EXPECTED_VERSION}" \
        "${E2E_EXPECTED_CODENAME}" <<'REMOTE_CHECKS' | tee "${installed_system_report}"
set -euo pipefail

expected_distro=$1
expected_id=$2
expected_version=$3
expected_codename=$4

source /etc/os-release
if [ "${expected_codename}" = "AUTO" ]; then
    expected_codename=${VERSION_CODENAME}
fi
if [ "${ID}" != "${expected_id}" ] || [ "${VERSION_ID}" != "${expected_version}" ] || [ "${VERSION_CODENAME}" != "${expected_codename}" ]; then
    echo "[ERROR] Expected ${expected_id} ${expected_version} (${expected_codename}), found ${PRETTY_NAME}"
    exit 1
fi

apt_sources=$(grep -R -h -E --include='*.list' --include='*.sources' \
    '^(deb |Suites:)' /etc/apt 2>/dev/null || true)
if ! grep -Eq "(^|[[:space:]])${expected_codename}([[:space:]-]|$)" <<<"${apt_sources}"; then
    echo "[ERROR] No ${expected_codename} APT source found on the installed system"
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

case "${expected_distro}" in
    debian)
        for debian_suite in bullseye bookworm trixie forky; do
            if [ "${debian_suite}" != "${expected_codename}" ] && \
                grep -R -q -E --include='*.list' --include='*.sources' \
                    "(^|[[:space:]])${debian_suite}([[:space:]-]|$)" /etc/apt 2>/dev/null; then
                echo "[ERROR] Found stale Debian suite ${debian_suite} in APT sources"
                exit 1
            fi
        done

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

        echo "tasksel family: ${tasksel_version}"
        echo "debconf family: ${debconf_version}"
        ;;
    ubuntu)
        ubuntu_minimal_version=$(package_version ubuntu-minimal)
        if ! grep -R -q -E --include='*.list' --include='*.sources' \
            'https?://[^[:space:]]*ubuntu\.com/ubuntu' /etc/apt 2>/dev/null; then
            echo "[ERROR] No official Ubuntu archive found in APT sources"
            exit 1
        fi
        if grep -R -H -E --include='*.list' --include='*.sources' \
            'https?://deb\.debian\.org/debian' /etc/apt 2>/dev/null; then
            echo "[ERROR] Found a Debian APT source on the installed Ubuntu system"
            exit 1
        fi
        echo "ubuntu-minimal: ${ubuntu_minimal_version}"
        ;;
    *)
        echo "[ERROR] Unsupported installed-system check: ${expected_distro}"
        exit 1
        ;;
esac

test -x /usr/src/dappnode/scripts/dappnode_install.sh
test -s /usr/src/dappnode/logs/iso_install.log
docker --version
docker compose version
docker info >/dev/null

echo "Installed OS: ${PRETTY_NAME}"
echo "[INFO] End-to-end ${expected_distro} ISO installation checks passed"
REMOTE_CHECKS

    echo "[INFO] Complete ${E2E_DISTRO} ISO installation succeeded"
}
