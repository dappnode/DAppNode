#!/bin/bash
# Runs an ISO end-to-end test inside a throwaway container:
#   test/e2e_in_docker.sh test/e2e_debian_iso.sh images/Dappnode-debian-...iso
#
# The container is its own network namespace, so the guest network from
# test/e2e_network.sh keeps its fixed interface name and addresses and never
# clashes with another job on the same host. Its TAP interface, NAT rules and
# dnsmasq go away with the container. The host needs only Docker, plus /dev/kvm
# for a usable speed: no sudo, and no packages besides Docker.
#
# E2E_* variables are passed through to the test. Files the test writes into the
# repository are given back to the calling user.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <test script> [args...] | --remove"
    exit 2
fi

# Marks this run's container, so --remove finds it even when this script was
# killed before its own trap could remove it, as when a job is cancelled.
run_label="dappnode-iso-e2e.run=${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"

if [ "${1}" = "--remove" ]; then
    docker ps --all --quiet --filter "label=${run_label}" | while IFS= read -r id; do
        docker rm --force --volumes "${id}" >/dev/null
    done
    exit
fi

give_back_output() {
    chown -R "${E2E_HOST_UID}:${E2E_HOST_GID}" "${REPO_ROOT}/test-output" 2>/dev/null || true
}

run_inside() {
    # Some Docker hosts only load the legacy iptables modules, and a container
    # cannot load the nf_tables ones itself.
    if ! iptables -t nat -S >/dev/null 2>&1; then
        update-alternatives --quiet --set iptables /usr/sbin/iptables-legacy
    fi

    trap give_back_output EXIT

    bash "${SCRIPT_DIR}/e2e_network.sh" up
    E2E_TAP_IFACE=${E2E_TAP_IFACE:-dne2e0} bash "$@"
}

if [ "${1}" = "--inside" ]; then
    shift
    run_inside "$@"
    exit
fi

image=${E2E_DOCKER_IMAGE:-dappnode-iso-e2e-runner}
container="dappnode-iso-e2e-${GITHUB_RUN_ID:-local}-${GITHUB_JOB:-job}-$$"
# Stop the test from inside, so a container survives a killed runner by this at most.
time_limit=${E2E_DOCKER_TIME_LIMIT:-85m}

docker build --quiet --tag "${image}" - <"${SCRIPT_DIR}/e2e.Dockerfile" >/dev/null

device_args=(--device /dev/net/tun)
if [ -c /dev/kvm ]; then
    device_args+=(--device /dev/kvm)
else
    echo "[WARN] /dev/kvm is missing; the install falls back to slow TCG emulation"
fi

env_args=(
    --env RUNNER_TEMP=/var/tmp/e2e
    --env E2E_HOST_UID="$(id -u)"
    --env E2E_HOST_GID="$(id -g)"
)
while IFS= read -r name; do
    env_args+=(--env "${name}")
done < <(compgen -e | grep -E '^(E2E_|KEEP_E2E_VM$)' || true)

remove_container() {
    docker rm --force --volumes "${container}" >/dev/null 2>&1 || true
}
trap remove_container EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The repository is mounted at its own path, so paths in logs and arguments match
# the host. VM disks go to an anonymous volume (RUNNER_TEMP), which --rm removes.
docker run --rm --init \
    --name "${container}" \
    --label "${run_label}" \
    --cap-add NET_ADMIN \
    --sysctl net.ipv4.ip_forward=1 \
    "${device_args[@]}" \
    --mount type=volume,destination=/var/tmp/e2e \
    "${env_args[@]}" \
    --volume "${REPO_ROOT}:${REPO_ROOT}" \
    --workdir "${PWD}" \
    "${image}" \
    timeout "${time_limit}" bash "${SCRIPT_DIR}/e2e_in_docker.sh" --inside "$@" &
# In the background, so a signal to this script runs its traps straight away.
wait "$!"
