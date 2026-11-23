# Tools the ISO end-to-end tests run with; see test/e2e_in_docker.sh.
FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        qemu-system-x86 qemu-utils ovmf socat sshpass openssh-client \
        dnsmasq-base iptables iproute2 && \
    rm -rf /var/lib/apt/lists/*
