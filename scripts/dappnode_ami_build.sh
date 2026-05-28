#!/bin/bash
# DAppNode AMI Build Script
# Purpose: Install prerequisites, pre-download core Docker images, and set up
# first-boot installer for EC2 Image Builder.
#
# Env vars:
#   PROFILE_URL — URL to dappnode_profile.sh with pinned versions (required)
#
# The installer still runs at first boot (via rc.local), but finds the heavy
# Docker images already cached in /usr/src/dappnode/DNCORE/, making boot fast.

set -euo pipefail

: "${PROFILE_URL:?PROFILE_URL env var is required}"

DAPPNODE_DIR="/usr/src/dappnode"
DNCORE_DIR="$DAPPNODE_DIR/DNCORE"
LOGS_DIR="$DAPPNODE_DIR/logs"
LOG_FILE="$LOGS_DIR/ami_build.log"

export DEBIAN_FRONTEND=noninteractive

mkdir -p "$DAPPNODE_DIR/scripts" "$DNCORE_DIR" "$LOGS_DIR"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[AMI-BUILD] $*"; }

lsb_dist="$(. /etc/os-release && echo "$ID")"
log "OS: $lsb_dist | Profile: $PROFILE_URL"

# ─── Phase 1: Prerequisites ──────────────────────────────────────────────────
log "=== Phase 1: Prerequisites ==="

apt-get update -y

if ! docker -v >/dev/null 2>&1; then
    log "Installing Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc || true
    apt-get install -y ca-certificates curl lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${lsb_dist}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$lsb_dist $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

cat >/usr/local/bin/docker-compose <<'EOL'
#!/bin/bash
docker compose "$@"
EOL
chmod +x /usr/local/bin/docker-compose

modprobe wireguard 2>/dev/null || apt-get install -y wireguard-dkms || apt-get install -y wireguard-tools || true
apt-get install -y lsof iptables xz-utils || true

# ─── Phase 2: Pre-download core images ───────────────────────────────────────
log "=== Phase 2: Pre-downloading core images ==="

wget -O "$DNCORE_DIR/.dappnode_profile" "$PROFILE_URL"

# Source only the version variables (up to ISOBUILD marker)
sed '/^\#\!ISOBUILD/q' "$DNCORE_DIR/.dappnode_profile" > /tmp/vars.sh
source /tmp/vars.sh

COMPONENTS=(BIND IPFS WIREGUARD DAPPMANAGER WIFI HTTPS)

for comp in "${COMPONENTS[@]}"; do
    ver="${comp}_VERSION"
    comp_lower="$(echo "$comp" | tr '[:upper:]' '[:lower:]')"
    VERSION="${!ver}"

    if [[ "$VERSION" == /ipfs/* ]]; then
        log "Skipping $comp (IPFS-based version)"
        continue
    fi

    BASE_URL="https://github.com/dappnode/DNP_${comp}/releases/download/v${VERSION}"

    log "Downloading $comp v${VERSION}..."
    wget -q -O "$DNCORE_DIR/${comp_lower}.dnp.dappnode.eth_${VERSION}_linux-amd64.txz" \
        "${BASE_URL}/${comp_lower}.dnp.dappnode.eth_${VERSION}_linux-amd64.txz" || \
        log "WARNING: Failed to download $comp image"

    wget -q -O "$DNCORE_DIR/docker-compose-${comp_lower}.yml" \
        "${BASE_URL}/docker-compose.yml" || \
        log "WARNING: Failed to download $comp compose"

    wget -q -O "$DNCORE_DIR/dappnode_package-${comp_lower}.json" \
        "${BASE_URL}/dappnode_package.json" || \
        log "WARNING: Failed to download $comp manifest"
done

# Content hashes for execution/consensus clients
CONTENT_HASH_PKGS=(besu geth nethermind erigon prysm teku lighthouse lodestar nimbus)
HASH_FILE="$DNCORE_DIR/packages-content-hash.csv"
rm -f "$HASH_FILE"
for pkg in "${CONTENT_HASH_PKGS[@]}"; do
    HASH=$(wget -q -O- "https://github.com/dappnode/DAppNodePackage-${pkg}/releases/latest/download/content-hash" || true)
    if [ -n "$HASH" ]; then
        echo "${pkg}.dnp.dappnode.eth,${HASH}" >> "$HASH_FILE"
        log "Got content hash: $pkg"
    fi
done

log "Pre-download complete:"
du -sh "$DNCORE_DIR/"

# ─── Phase 3: First-boot installer ───────────────────────────────────────────
log "=== Phase 3: First-boot setup ==="

wget -O "$DAPPNODE_DIR/scripts/dappnode_install.sh" https://installer.dappnode.io
chmod +x "$DAPPNODE_DIR/scripts/dappnode_install.sh"

cat > /etc/rc.local << 'RC'
#!/bin/sh -e
/usr/src/dappnode/scripts/dappnode_install.sh
exit 0
RC
chmod +x /etc/rc.local
touch "$DAPPNODE_DIR/.firstboot"

log "=== AMI build complete ==="
