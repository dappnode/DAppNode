#!/bin/bash
# Boots an unattended DAppNode ISO as USB media and installs it onto a virtual disk.
# It completes the first-boot flow, reboots, and validates the running DAppNode system.
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

    local required_commands=(qemu-img qemu-system-x86_64 ssh sshpass socat)
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
    local installer_serial_log="${output_dir}/installer-serial.log"
    local installer_process_log="${output_dir}/installer-qemu.log"
    local installer_monitor_socket="${vm_dir}/installer-monitor.sock"
    local installer_screenshot="${output_dir}/installer-screen.ppm"
    local first_boot_monitor_socket="${vm_dir}/first-boot-monitor.sock"
    local first_boot_screenshot="${output_dir}/first-boot-screen.ppm"
    local first_boot_serial_log="${output_dir}/first-boot-serial.log"
    local first_boot_process_log="${output_dir}/first-boot-qemu.log"
    local system_serial_log="${output_dir}/final-system-serial.log"
    local system_process_log="${output_dir}/final-system-qemu.log"
    local installed_system_report="${output_dir}/installed-system-report.log"

    local vm_disk_size=${E2E_VM_DISK_SIZE:-32G}
    local vm_memory_mb=${E2E_VM_MEMORY_MB:-4096}
    local vm_cpus=${E2E_VM_CPUS:-2}
    local install_timeout_seconds=${E2E_INSTALL_TIMEOUT_SECONDS:-3600}
    local boot_timeout_seconds=${E2E_BOOT_TIMEOUT_SECONDS:-600}
    local first_boot_timeout_seconds=${E2E_FIRST_BOOT_TIMEOUT_SECONDS:-1800}
    local postinstall_timeout_seconds=${E2E_POSTINSTALL_TIMEOUT_SECONDS:-1200}
    local ssh_port=${E2E_SSH_PORT:-2222}
    local ssh_password=${E2E_SSH_PASSWORD:-dappnode.s0}
    local boot_mode=${E2E_BOOT_MODE:-usb}
    local firmware=${E2E_FIRMWARE:-uefi}
    qemu_pid=""

    if [ "${boot_mode}" != "usb" ] || [ "${firmware}" != "uefi" ]; then
        echo "[ERROR] This unattended ISO test requires E2E_BOOT_MODE=usb and E2E_FIRMWARE=uefi"
        return 1
    fi

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
        if [ -S "${installer_monitor_socket}" ]; then
            printf 'screendump %s\n' "${installer_screenshot}" | \
                socat - "UNIX-CONNECT:${installer_monitor_socket}" >/dev/null 2>&1 || true
        fi
        if [ -S "${first_boot_monitor_socket}" ]; then
            printf 'screendump %s\n' "${first_boot_screenshot}" | \
                socat - "UNIX-CONNECT:${first_boot_monitor_socket}" >/dev/null 2>&1 || true
        fi
        echo "[INFO] Last installer serial output:"
        tail -n 200 "${installer_serial_log}" 2>/dev/null || true
        echo "[INFO] Last first-boot serial output:"
        tail -n 200 "${first_boot_serial_log}" 2>/dev/null || true
        echo "[INFO] Last final-system serial output:"
        tail -n 200 "${system_serial_log}" 2>/dev/null || true
        echo "[INFO] QEMU process output:"
        tail -n 100 "${installer_process_log}" 2>/dev/null || true
        tail -n 100 "${first_boot_process_log}" 2>/dev/null || true
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

    local ovmf_code=""
    local ovmf_vars=""
    local ovmf_candidate
    for ovmf_candidate in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
        if [ -f "${ovmf_candidate}" ]; then
            ovmf_code=${ovmf_candidate}
            break
        fi
    done
    for ovmf_candidate in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
        if [ -f "${ovmf_candidate}" ]; then
            ovmf_vars=${ovmf_candidate}
            break
        fi
    done
    if [ -z "${ovmf_code}" ] || [ -z "${ovmf_vars}" ]; then
        echo "[ERROR] UEFI firmware files were not found; install the ovmf package"
        return 1
    fi
    local writable_ovmf_vars="${vm_dir}/OVMF_VARS.fd"
    cp "${ovmf_vars}" "${writable_ovmf_vars}"
    local firmware_args=(
        -drive "if=pflash,format=raw,readonly=on,file=${ovmf_code}"
        -drive "if=pflash,format=raw,file=${writable_ovmf_vars}"
    )

    echo "[INFO] Creating ${vm_disk_size} virtual installation disk"
    qemu-img create -q -f qcow2 "${disk_path}" "${vm_disk_size}"

    local target_disk_install_args=(
        -drive "file=${disk_path},format=qcow2,if=none,id=target_disk"
        -device "virtio-blk-pci,drive=target_disk,bootindex=2"
    )
    local installer_media_args=(
        -device "qemu-xhci,id=installer_xhci"
        -drive "file=${iso_path},format=raw,if=none,readonly=on,id=installer_media"
        -device "usb-storage,drive=installer_media,bootindex=1"
    )

    echo "[INFO] Booting the unattended ${E2E_DISTRO} ISO as ${firmware}/${boot_mode}"
    qemu-system-x86_64 \
        "${qemu_acceleration[@]}" \
        "${firmware_args[@]}" \
        -m "${vm_memory_mb}" \
        -smp "${vm_cpus}" \
        "${target_disk_install_args[@]}" \
        "${installer_media_args[@]}" \
        -boot menu=off \
        -nic user,model=virtio-net-pci \
        -display none \
        -monitor "unix:${installer_monitor_socket},server=on,wait=off" \
        -serial "file:${installer_serial_log}" \
        -no-reboot \
        >"${installer_process_log}" 2>&1 &
    qemu_pid=$!

    if ! wait_for_process_exit "${qemu_pid}" "${install_timeout_seconds}" "the ${E2E_DISTRO} installer to complete"; then
        show_failure_logs
        return 1
    fi
    qemu_pid=""

    echo "[INFO] Installer completed and virtual USB removed; starting the first disk boot"
    qemu-system-x86_64 \
        "${qemu_acceleration[@]}" \
        "${firmware_args[@]}" \
        -m "${vm_memory_mb}" \
        -smp "${vm_cpus}" \
        -drive "file=${disk_path},format=qcow2,if=none,id=target_disk" \
        -device "virtio-blk-pci,drive=target_disk,bootindex=1" \
        -boot menu=off \
        -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${ssh_port}-:22" \
        -display none \
        -monitor "unix:${first_boot_monitor_socket},server=on,wait=off" \
        -serial "file:${first_boot_serial_log}" \
        -no-reboot \
        >"${first_boot_process_log}" 2>&1 &
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

    wait_for_ssh() {
        local description=$1
        local timeout_seconds=$2
        local deadline=$((SECONDS + timeout_seconds))

        echo "[INFO] Waiting for SSH on ${description}"
        while ! ssh_guest true >/dev/null 2>&1; do
            if ! kill -0 "${qemu_pid}" 2>/dev/null; then
                echo "[ERROR] ${description} VM exited before SSH became available"
                return 1
            fi
            if [ "${SECONDS}" -ge "${deadline}" ]; then
                echo "[ERROR] Timed out waiting for SSH on ${description}"
                return 1
            fi
            sleep 10
        done
    }

    wait_for_guest_command() {
        local timeout_seconds=$1
        local description=$2
        local guest_command=$3
        local deadline=$((SECONDS + timeout_seconds))

        echo "[INFO] Waiting for ${description}"
        while ! ssh_guest "${guest_command}" >/dev/null 2>&1; do
            if ! kill -0 "${qemu_pid}" 2>/dev/null; then
                echo "[ERROR] VM exited while waiting for ${description}"
                return 1
            fi
            if [ "${SECONDS}" -ge "${deadline}" ]; then
                echo "[ERROR] Timed out waiting for ${description}"
                return 1
            fi
            sleep 10
        done
    }

    if ! wait_for_ssh "the first installed-system boot" "${boot_timeout_seconds}"; then
        show_failure_logs
        return 1
    fi

    if ! wait_for_guest_command \
        "${first_boot_timeout_seconds}" \
        "DAppNode's first-boot installation test" \
        "test ! -e /usr/src/dappnode/.firstboot"; then
        show_failure_logs
        return 1
    fi

    echo "[INFO] Acknowledging the completed first-boot test"
    printf 'sendkey ret\n' | \
        socat - "UNIX-CONNECT:${first_boot_monitor_socket}" >/dev/null

    if ! wait_for_guest_command \
        120 \
        "the first-boot installer process to exit" \
        "! pgrep -f '[d]appnode_test_install.sh|[/]usr/src/dappnode/scripts/dappnode_install.sh' >/dev/null"; then
        show_failure_logs
        return 1
    fi

    echo "[INFO] Rebooting after the completed first-boot test"
    ssh_guest "sudo -S -p '' systemctl reboot" <<<"${ssh_password}" >/dev/null 2>&1 || true
    if ! wait_for_process_exit "${qemu_pid}" 120 "the first-boot VM to request its reboot"; then
        show_failure_logs
        return 1
    fi
    qemu_pid=""

    echo "[INFO] Starting the final installed system without the virtual USB"
    qemu-system-x86_64 \
        "${qemu_acceleration[@]}" \
        "${firmware_args[@]}" \
        -m "${vm_memory_mb}" \
        -smp "${vm_cpus}" \
        -drive "file=${disk_path},format=qcow2,if=none,id=target_disk" \
        -device "virtio-blk-pci,drive=target_disk,bootindex=1" \
        -boot menu=off \
        -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${ssh_port}-:22" \
        -display none \
        -monitor none \
        -serial "file:${system_serial_log}" \
        >"${system_process_log}" 2>&1 &
    qemu_pid=$!

    if ! wait_for_ssh "the final installed system" "${boot_timeout_seconds}"; then
        show_failure_logs
        return 1
    fi

    if ! wait_for_guest_command \
        "${postinstall_timeout_seconds}" \
        "DAppNode core services to start" \
        "test ! -e /usr/src/dappnode/.firstboot && ! grep -Fq '/usr/src/dappnode/scripts/dappnode_install.sh' /etc/rc.local && docker ps --format '{{.Names}}' | grep -Fxq 'DAppNodeCore-dappmanager.dnp.dappnode.eth'"; then
        show_failure_logs
        return 1
    fi

    echo "[INFO] Validating the completed unattended ${E2E_DISTRO} USB installation"
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
test -s /usr/src/dappnode/logs/dappnode_install.log
test ! -e /usr/src/dappnode/.firstboot
! grep -Fq '/usr/src/dappnode/scripts/dappnode_install.sh' /etc/rc.local
docker --version
docker compose version
docker info >/dev/null
docker ps --format '{{.Names}}' | grep -Fxq 'DAppNodeCore-dappmanager.dnp.dappnode.eth'

echo "Installed OS: ${PRETTY_NAME}"
echo "[INFO] End-to-end unattended ${expected_distro} UEFI USB installation checks passed"
REMOTE_CHECKS

    echo "[INFO] Complete unattended ${E2E_DISTRO} UEFI USB installation succeeded"
}
