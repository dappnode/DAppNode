#!/bin/bash
# DAppNode AMI Build Script
# Purpose: Install prerequisites, pre-download core Docker images, and set up
# first-boot installer for EC2 Image Builder.
#
# The installer still runs at first boot (via rc.local), but finds the heavy
# Docker images already cached in /usr/src/dappnode/DNCORE/, making boot fast
# and not dependent on network for bulk downloads.

set -euo pipefail

DAPPNODE_DIR="/usr/src/dappnode"
DNCORE_DIR="$DAPPNODE_DIR/DNCORE"
LOGS_DIR="$DAPPNODE_DIR/logs"
LOG_FILE="$LOGS_DIR/ami_build.log"

mkdir -p "$DAPPNODE_DIR/scripts" "$DNCORE_DIR" "$LOGS_DIR"
touch "$LOG_FILE"

log() { echo "[AMI-BUILD] $*" | tee -a "$LOG_FILE"; }

lsb_dist="$(. /etc/os-release && echo "$ID")"
log "Detected OS: $lsb_dist"

# ─── Docker ───────────────────────────────────────────────────────────────────
install_docker() {
    log "Installing Docker..."
    apt-get update -y
    apt-get remove -y docker docker-engine docker.io containerd runc || true

    apt-get install -y ca-certificates curl lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${lsb_dist}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$lsb_dist $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list >/dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    [ -f "/usr/bin/xz" ] || apt-get install -y xz-utils
    log "Docker installed successfully"
}

# ─── Docker Compose alias (legacy compatibility) ──────────────────────────────
install_compose_alias() {
    cat >/usr/local/bin/docker-compose <<'EOL'
#!/bin/bash
docker compose "$@"
EOL
    chmod +x /usr/local/bin/docker-compose
}

# ─── Prerequisites ────────────────────────────────────────────────────────────
log "=== Phase 1: Prerequisites ==="

apt-get update -y | tee -a "$LOG_FILE"

if ! docker -v >/dev/null 2>&1; then
    install_docker 2>&1 | tee -a "$LOG_FILE"
else
    log "Docker already installed"
fi

install_compose_alias

modprobe wireguard 2>/dev/null || apt-get install -y wireguard-dkms || apt-get install -y wireguard-tools || true
apt-get install -y lsof iptables xz-utils || true

# ─── Pre-download core Docker images ─────────────────────────────────────────
log "=== Phase 2: Pre-downloading core images ==="

# Download latest released profile (contains version pins)
wget -O "$DNCORE_DIR/.dappnode_profile" \
    "https://github.com/dappnode/DAppNode/releases/latest/download/dappnode_profile.sh"

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

# Grab content hashes for execution/consensus clients
CONTENT_HASH_PKGS=(besu geth nethermind erigon prysm teku lighthouse lodestar nimbus)
HASH_FILE="$DNCORE_DIR/packages-content-hash.csv"
rm -f "$HASH_FILE"
for pkg in "${CONTENT_HASH_PKGS[@]}"; do
    HASH=$(wget -q -O- "https://github.com/dappnode/DAppNodePackage-${pkg}/releases/latest/download/content-hash" || true)
    if [ -n "$HASH" ]; then
        echo "${pkg}.dnp.dappnode.eth,${HASH}" >> "$HASH_FILE"
        log "Got content hash for $pkg"
    fi
done

log "Pre-download complete:"
ls -lh "$DNCORE_DIR/"
du -sh "$DNCORE_DIR/"

# ─── Set up first-boot installer ─────────────────────────────────────────────
log "=== Phase 3: First-boot installer ==="

wget -O "$DAPPNODE_DIR/scripts/dappnode_install.sh" https://installer.dappnode.io
chmod +x "$DAPPNODE_DIR/scripts/dappnode_install.sh"

cat > /etc/rc.local << 'RC'
#!/bin/sh -e
/usr/src/dappnode/scripts/dappnode_install.sh
exit 0
RC
chmod +x /etc/rc.local
touch "$DAPPNODE_DIR/.firstboot"

log "=== AMI build complete. First boot will find pre-cached images in DNCORE/ ==="
