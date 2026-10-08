#!/bin/bash
# Creates the TAP network the E2E guests boot on. Run as root: up | down
# The guest gets DHCP, DNS and NAT like on a home LAN. CI providers drop outbound
# ICMP, so echo requests from the guest are answered by this host instead: the
# DAppNode first-boot check pings google.com and must see a reply.
set -Eeuo pipefail

E2E_TAP_IFACE=${E2E_TAP_IFACE:-dne2e0}
E2E_HOST_IP=${E2E_HOST_IP:-192.168.77.1}
E2E_GUEST_IP=${E2E_GUEST_IP:-192.168.77.10}
E2E_GUEST_MAC=${E2E_GUEST_MAC:-52:54:00:d4:00:10}
SUBNET="${E2E_HOST_IP%.*}.0/24"
STATE_DIR=${E2E_NETWORK_STATE_DIR:-/run/dappnode-e2e}

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] $0 must run as root"
    exit 1
fi

tap_owner=${SUDO_USER:-root}

network_up() {
    mkdir -p "${STATE_DIR}"

    ip tuntap add dev "${E2E_TAP_IFACE}" mode tap user "${tap_owner}"
    ip addr add "${E2E_HOST_IP}/24" dev "${E2E_TAP_IFACE}"
    ip link set "${E2E_TAP_IFACE}" up

    sysctl -q -w net.ipv4.ip_forward=1
    iptables -t nat -A POSTROUTING -s "${SUBNET}" ! -o "${E2E_TAP_IFACE}" -j MASQUERADE
    iptables -t nat -A PREROUTING -i "${E2E_TAP_IFACE}" -p icmp --icmp-type echo-request \
        -j DNAT --to-destination "${E2E_HOST_IP}"
    # Docker sets the FORWARD policy to DROP, so allow the guest explicitly.
    iptables -I FORWARD 1 -i "${E2E_TAP_IFACE}" -j ACCEPT
    iptables -I FORWARD 1 -o "${E2E_TAP_IFACE}" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    local upstream=(--resolv-file=/etc/resolv.conf)
    if [ -f /run/systemd/resolve/resolv.conf ]; then
        # The stub at 127.0.0.53 is fine for the host, but read the real upstreams.
        upstream=(--resolv-file=/run/systemd/resolve/resolv.conf)
    fi

    # Stay root: the state directory may live in a workspace other users cannot enter.
    dnsmasq \
        --interface="${E2E_TAP_IFACE}" \
        --bind-interfaces \
        --except-interface=lo \
        --listen-address="${E2E_HOST_IP}" \
        --dhcp-range="${E2E_GUEST_IP},${E2E_GUEST_IP},255.255.255.0,12h" \
        --dhcp-host="${E2E_GUEST_MAC},${E2E_GUEST_IP}" \
        --dhcp-option=option:router,"${E2E_HOST_IP}" \
        --dhcp-option=option:dns-server,"${E2E_HOST_IP}" \
        --dhcp-leasefile="${STATE_DIR}/dnsmasq.leases" \
        --pid-file="${STATE_DIR}/dnsmasq.pid" \
        --log-facility="${STATE_DIR}/dnsmasq.log" \
        --log-dhcp \
        --no-hosts \
        --user=root \
        "${upstream[@]}"

    echo "[INFO] Guest network ${E2E_TAP_IFACE} is up: host ${E2E_HOST_IP}, guest ${E2E_GUEST_IP} (${E2E_GUEST_MAC})"
}

network_down() {
    if [ -f "${STATE_DIR}/dnsmasq.pid" ]; then
        kill "$(cat "${STATE_DIR}/dnsmasq.pid")" 2>/dev/null || true
    fi
    iptables -D FORWARD -o "${E2E_TAP_IFACE}" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "${E2E_TAP_IFACE}" -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "${E2E_TAP_IFACE}" -p icmp --icmp-type echo-request \
        -j DNAT --to-destination "${E2E_HOST_IP}" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s "${SUBNET}" ! -o "${E2E_TAP_IFACE}" -j MASQUERADE 2>/dev/null || true
    ip link delete "${E2E_TAP_IFACE}" 2>/dev/null || true
    rm -rf "${STATE_DIR}"
}

case "${1:-}" in
    up) network_up ;;
    down) network_down ;;
    *)
        echo "Usage: $0 up|down"
        exit 2
        ;;
esac
