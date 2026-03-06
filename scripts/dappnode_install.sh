#!/bin/bash

# This installer is written for bash. It's safe to *run it from zsh* (it will execute via bash
# thanks to the shebang), but users sometimes invoke it as `zsh ./script.sh` or `source ./script.sh`.
# - If sourced, bail out (sourcing would pollute the current shell and can break it).
# - If invoked by a non-bash shell, re-exec with bash before hitting bash-specific builtins.
if (return 0 2>/dev/null); then
    echo "This script must be executed, not sourced. Run: bash $0"
    return 1
fi

if [ -z "${BASH_VERSION:-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -Eeuo pipefail

# Optional env inputs (avoid unbound-variable errors under `set -u`)
: "${UPDATE:=false}"
: "${STATIC_IP:=}"
: "${LOCAL_PROFILE_PATH:=}"
: "${MINIMAL:=false}"
: "${LITE:=false}"
: "${PACKAGES:=}"

# Enable alias expansion in non-interactive bash scripts.
# Required so commands like `dappnode_wireguard` (defined as aliases in `.dappnode_profile`) work.
shopt -s expand_aliases

# Ensure array is always defined (avoid `set -u` edge cases)
DNCORE_COMPOSE_ARGS=()

##############################
# Logging / Errors            #
##############################

log() {
    # LOGFILE is created after dir bootstrap; until then we just print to stdout.
    if [[ -n "${LOGFILE:-}" && -d "${LOGS_DIR:-}" ]]; then
        printf '%s\n' "$*" | tee -a "$LOGFILE"
    else
        printf '%s\n' "$*"
    fi
}

warn() {
    log "[WARN] $*"
}

die() {
    log "[ERROR] $*"
    exit 1
}

usage() {
    cat <<'EOF'
Usage: dappnode_install.sh [options]

Options:
  --update                      Clean existing downloaded artifacts before installing (equivalent: UPDATE=true)
  --static-ip <ipv4>            Set a static IP (equivalent: STATIC_IP=...)
  --local-profile-path <path>   Use a local .dappnode_profile instead of downloading (equivalent: LOCAL_PROFILE_PATH=...)
  --ipfs-endpoint <url>         Override IPFS gateway endpoint (equivalent: IPFS_ENDPOINT=...)
  --profile-url <url>           Override profile download URL (equivalent: PROFILE_URL=...)
  --minimal                     Install only BIND DAPPMANAGER NOTIFICATIONS PREMIUM (equivalent: MINIMAL=true)
  --lite                        Install reduced package set: BIND VPN WIREGUARD DAPPMANAGER NOTIFICATIONS PREMIUM (equivalent: LITE=true)
  --packages <list>             Override package selection (comma or space separated), e.g. BIND,IPFS,VPN
  -h, --help                    Show this help

Environment variables (also supported):
        UPDATE, STATIC_IP, LOCAL_PROFILE_PATH, IPFS_ENDPOINT, PROFILE_URL, MINIMAL, LITE, PACKAGES
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --update)
                UPDATE=true
                shift
                ;;
            --static-ip)
                [[ $# -ge 2 ]] || die "--static-ip requires an IPv4 argument"
                STATIC_IP="$2"
                shift 2
                ;;
            --local-profile-path)
                [[ $# -ge 2 ]] || die "--local-profile-path requires a path argument"
                LOCAL_PROFILE_PATH="$2"
                shift 2
                ;;
            --ipfs-endpoint)
                [[ $# -ge 2 ]] || die "--ipfs-endpoint requires a URL argument"
                IPFS_ENDPOINT="$2"
                shift 2
                ;;
            --profile-url)
                [[ $# -ge 2 ]] || die "--profile-url requires a URL argument"
                PROFILE_URL="$2"
                shift 2
                ;;
            --minimal)
                MINIMAL=true
                shift
                ;;
            --lite)
                LITE=true
                shift
                ;;
            --packages)
                [[ $# -ge 2 ]] || die "--packages requires a package list argument"
                PACKAGES="$2"
                shift 2
                ;;
            --packages=*)
                PACKAGES="${1#*=}"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                die "Unknown option: $1 (use --help)"
                ;;
        esac
    done
}

validate_install_mode() {
    if [[ "${MINIMAL}" == "true" && "${LITE}" == "true" ]]; then
        die "--minimal and --lite are mutually exclusive"
    fi
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
}

require_downloader() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        return 0
    fi
    die "Missing required downloader: install curl or wget"
}

check_prereqs() {
    require_cmd docker
    require_downloader

    # Ensure compose is available (Docker Desktop / modern docker engine)
    if ! docker compose version >/dev/null 2>&1; then
        die "Docker Compose not available (expected: 'docker compose'). Update Docker or install the compose plugin."
    fi
}

# Wait until dappmanager publishes INTERNAL_IP via its local HTTP endpoint.
# Runs the curl inside the provided container and exits with error on timeout.
# Usage: wait_for_internal_ip <container_name> [timeout_seconds] [initial_sleep_seconds]
wait_for_internal_ip() {
    local container_name="$1"
    local timeout_seconds="${2:-120}"
    local initial_sleep_seconds="${3:-10}"
    local internal_ip_url="http://127.0.0.1/global-envs/INTERNAL_IP"
    local hostname_url="http://127.0.0.1/global-envs/HOSTNAME"

    echo "Waiting for dappmanager to publish INTERNAL_IP and HOSTNAME..."
    sleep "$initial_sleep_seconds"

    local start_seconds internal_http_code internal_value internal_result
    local hostname_http_code hostname_value hostname_result
    start_seconds=$SECONDS
    internal_http_code=""
    internal_value=""
    hostname_http_code=""
    hostname_value=""

    while true; do
        if (( SECONDS - start_seconds >= timeout_seconds )); then
            die "Timed out after ${timeout_seconds}s waiting for INTERNAL_IP and HOSTNAME from dappmanager (expected HTTP 200 with non-empty values). Last seen: INTERNAL_IP code=${internal_http_code:-?} value=${internal_value:-<empty>}; HOSTNAME code=${hostname_http_code:-?} value=${hostname_value:-<empty>}"
        fi

        # Must be executed inside the dappmanager container.
        # Return format is:
        #   <body>\n<http_code>
        # Parse in bash (not inside container sh) to avoid shell portability issues.

        internal_result="$(
            docker exec -i "$container_name" sh -lc "curl -sS -w '\n%{http_code}' '$internal_ip_url' 2>/dev/null || true" 2>/dev/null || true
        )"
        internal_http_code="$(printf '%s\n' "$internal_result" | tail -n 1 | tr -d '\r')"
        internal_value="$(printf '%s\n' "$internal_result" | head -n 1 | tr -d '\r' | xargs)"

        hostname_result="$(
            docker exec -i "$container_name" sh -lc "curl -sS -w '\n%{http_code}' '$hostname_url' 2>/dev/null || true" 2>/dev/null || true
        )"
        hostname_http_code="$(printf '%s\n' "$hostname_result" | tail -n 1 | tr -d '\r')"
        hostname_value="$(printf '%s\n' "$hostname_result" | head -n 1 | tr -d '\r' | xargs)"

        if [[ "$internal_http_code" == "200" && -n "$internal_value" && "$internal_value" != "null" && "$hostname_http_code" == "200" && -n "$hostname_value" && "$hostname_value" != "null" ]]; then
            sleep 2 # Extra buffer to ensure values are fully propagated before we proceed
            echo "INTERNAL_IP is ready: $internal_value"
            echo "HOSTNAME is ready: $hostname_value"
            return 0
        fi

        echo "INTERNAL_IP/HOSTNAME not ready yet (INTERNAL_IP code=${internal_http_code:-?}, HOSTNAME code=${hostname_http_code:-?}). Retrying..."
        sleep 2
    done
}

# Print VPN access credentials (Wireguard + OpenVPN) after core has started.
# Works on both Linux and macOS as long as the relevant containers are running.
print_vpn_access_credentials() {
    local localhost_flag=()
    local has_wireguard=false
    local has_vpn=false
    local pkg

    if $IS_MACOS; then
        localhost_flag=(--localhost)
    fi

    for pkg in "${PKGS[@]}"; do
        if [[ "$pkg" == "WIREGUARD" ]]; then
            has_wireguard=true
        elif [[ "$pkg" == "VPN" ]]; then
            has_vpn=true
        fi
    done

    if [[ "$has_wireguard" != "true" && "$has_vpn" != "true" ]]; then
        echo ""
        echo "No VPN package selected (VPN/WIREGUARD). Skipping credentials output."
        return 0
    fi

    echo ""
    echo "Waiting for VPN initialization..."
    wait_for_internal_ip "DAppNodeCore-dappmanager.dnp.dappnode.eth" 120 20

    echo ""
    echo "##############################################"
    echo "#      DAppNode VPN Access Credentials        #"
    echo "##############################################"
    echo ""
    echo "Your DAppNode is ready! Connect using your preferred VPN client."
    echo "Choose either Wireguard (recommended) or OpenVPN and import the"
    echo "credentials below into your VPN app to access your DAppNode."
    echo ""

    if [[ "$has_wireguard" == "true" ]]; then
        echo "--- Wireguard ---"
        docker exec -i DAppNodeCore-api.wireguard.dnp.dappnode.eth getWireguardCredentials "${localhost_flag[@]}" 2>&1 || \
            echo "Wireguard credentials not yet available. Try later with: dappnode_wireguard${localhost_flag:+ ${localhost_flag[*]}}"
    fi

    if [[ "$has_wireguard" == "true" && "$has_vpn" == "true" ]]; then
        echo ""
    fi

    if [[ "$has_vpn" == "true" ]]; then
        echo "--- OpenVPN ---"
        docker exec -i DAppNodeCore-vpn.dnp.dappnode.eth vpncli get dappnode_admin "${localhost_flag[@]}" 2>&1 || \
            echo "OpenVPN credentials not yet available. Try later with: dappnode_openvpn_get dappnode_admin${localhost_flag:+ ${localhost_flag[*]}}"
    fi

    echo ""
    echo "Import the configuration above into your VPN client of choice to access your DAppNode at http://my.dappnode"
}

# Build docker compose "-f <file>" args from downloaded compose files.
# This avoids depending on alias expansion or profile-generated strings.
build_dncore_compose_args() {
    DNCORE_COMPOSE_ARGS=()
    local file
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        DNCORE_COMPOSE_ARGS+=( -f "$file" )
    done < <(find "${DAPPNODE_CORE_DIR}" -name 'docker-compose-*.yml' -print 2>/dev/null | sort)
}

##################
# OS DETECTION   #
##################
OS_TYPE="$(uname -s)"
IS_MACOS=false
IS_LINUX=false
if [[ "$OS_TYPE" == "Darwin" ]]; then
    IS_MACOS=true
elif [[ "$OS_TYPE" == "Linux" ]]; then
    IS_LINUX=true
else
    die "Unsupported operating system: $OS_TYPE"
fi

#############
# VARIABLES #
#############
# Dirs - macOS uses $HOME/dappnode, Linux uses /usr/src/dappnode
if $IS_MACOS; then
    DAPPNODE_DIR="$HOME/dappnode"
else
    DAPPNODE_DIR="/usr/src/dappnode"
fi
DAPPNODE_CORE_DIR="${DAPPNODE_DIR}/DNCORE"
LOGS_DIR="$DAPPNODE_DIR/logs"
# Files
CONTENT_HASH_FILE="${DAPPNODE_CORE_DIR}/packages-content-hash.csv"
LOGFILE="${LOGS_DIR}/dappnode_install.log"
DAPPNODE_PROFILE="${DAPPNODE_CORE_DIR}/.dappnode_profile"
# Linux-only paths
if $IS_LINUX; then
    MOTD_FILE="/etc/motd"
    UPDATE_MOTD_DIR="/etc/update-motd.d"
fi
# Get URLs
IPFS_ENDPOINT=${IPFS_ENDPOINT:-"https://ipfs-gateway-dev.dappnode.net"}
# PROFILE_URL env is used to fetch the core packages versions that will be used to build the release in script install method
PROFILE_URL=${PROFILE_URL:-"https://github.com/dappnode/DAppNode/releases/latest/download/dappnode_profile.sh"}
DAPPNODE_ACCESS_CREDENTIALS="${DAPPNODE_DIR}/scripts/dappnode_access_credentials.sh"
DAPPNODE_ACCESS_CREDENTIALS_URL="https://github.com/dappnode/DAppNode/releases/latest/download/dappnode_access_credentials.sh"
# Other

# Architecture detection (cross-platform)
if $IS_MACOS; then
    ARCH="$(uname -m)"
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
    # arm64 is already correct for Apple Silicon
else
    ARCH="$(dpkg --print-architecture)"
fi

##############################
# Cross-platform Helpers     #
##############################

# Download a file: download_file <destination> <url>
download_file() {
    local dest="$1"
    local url="$2"
    log "Downloading from $url to $dest"
    mkdir -p "$(dirname "$dest")"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url"
        return
    fi
    wget -q --show-progress --progress=bar:force -O "$dest" "$url"
}

# Download content to stdout: download_stdout <url>
download_stdout() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url"
        return
    fi
    wget -q -O- "$url"
}

# Normalize IPFS refs and (if needed) infer the missing :<version> from dappnode_package.json
# Accepts:
#   - /ipfs/<cid>:<version>
#   - /ipfs/<cid>               (version inferred)
#   - ipfs/<cid>[:<version>]    (leading slash normalized)
normalize_ipfs_version_ref() {
    local raw_ref="$1"
    local comp="$2"
    local ref="$raw_ref"

    if [[ "$ref" == ipfs/* ]]; then
        ref="/$ref"
    fi

    # If it already has :<version>, we're done
    if [[ "$ref" == /ipfs/*:* ]]; then
        echo "$ref"
        return 0
    fi

    # If it's an IPFS ref without a :<version>, infer it from the manifest in the CID
    if [[ "$ref" == /ipfs/* ]]; then
        local cid_path="$ref"
        local manifest_url="${IPFS_ENDPOINT%/}${cid_path}/dappnode_package.json"
        local manifest
        manifest="$(download_stdout "$manifest_url" 2>/dev/null || true)"
        if [[ -z "$manifest" ]]; then
            echo "[ERROR] Could not fetch IPFS manifest for ${comp} from: $manifest_url" 1>&2
            echo "[ERROR] Provide ${comp}_VERSION as /ipfs/<cid>:<version> (example: /ipfs/Qm...:0.2.11)" 1>&2
            return 1
        fi

        local inferred_version
        inferred_version="$(
            echo "$manifest" |
                tr -d '\r' |
                grep -m1 '"version"' |
                sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^\"]+)".*/\1/'
        )"

        if [[ -z "$inferred_version" || "$inferred_version" == "$manifest" ]]; then
            echo "[ERROR] Could not infer version for ${comp} from IPFS manifest: $manifest_url" 1>&2
            echo "[ERROR] Provide ${comp}_VERSION as /ipfs/<cid>:<version>" 1>&2
            return 1
        fi

        echo "${cid_path}:${inferred_version}"
        return 0
    fi

    # Not an IPFS ref; return as-is
    echo "$raw_ref"
}

# Cross-platform in-place sed (macOS requires '' after -i)
sed_inplace() {
    if $IS_MACOS; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

##############################
# Compose Patching Helpers   #
##############################

# Remove journald logging from compose files (not supported on macOS Docker Desktop)
remove_logging_section() {
    local file="$1"
    sed_inplace '/logging/d;/journald/d' "$file"
}

# TODO: review difference between this and patch_compose_paths
# Replace Linux paths with macOS paths in compose files
patch_compose_paths() {
    local file="$1"
    sed_inplace "s|/usr/src/dappnode|${DAPPNODE_DIR}|g" "$file"
}

# Patch dappmanager compose for macOS: inject env vars the container needs
# to know the host core-dir path and to skip host-only operations,
# and fix the DNCORE volume mount to use the macOS host path.
patch_dappmanager_compose_for_macos() {
    local file="$1"

    # Replace the host side of the DNCORE volume mount with the actual DAPPNODE_CORE_DIR value
    # e.g. /usr/src/dappnode/DNCORE/:/usr/src/app/DNCORE/ -> $HOME/dappnode/DNCORE/:/usr/src/app/DNCORE/
    sed_inplace "s|[^[:space:]]*:/usr/src/app/DNCORE/|${DAPPNODE_CORE_DIR}/:/usr/src/app/DNCORE/|" "$file"

    local envs_to_add=()

    # DAPPNODE_CORE_DIR: lets the container know the host's DNCORE path
    if ! grep -q "DAPPNODE_CORE_DIR" "$file"; then
        envs_to_add+=("      - DAPPNODE_CORE_DIR=${DAPPNODE_CORE_DIR}")
    fi

    # DISABLE_HOST_SCRIPTS: tells the container to skip host-only scripts
    if ! grep -q "DISABLE_HOST_SCRIPTS" "$file"; then
        envs_to_add+=("      - DISABLE_HOST_SCRIPTS=${DISABLE_HOST_SCRIPTS}")
    fi

    [[ ${#envs_to_add[@]} -gt 0 ]] || return 0

    local tmp="${file}.tmp"
    local insert_file="${file}.envinsert"

    # macOS ships BSD awk, which can error with "newline in string" if a -v argument contains
    # literal newlines. Write the insertion block to a temp file and have awk read it.
    printf '%s\n' "${envs_to_add[@]}" >"$insert_file"

    awk -v insfile="$insert_file" '
        /^[[:space:]]*environment:[[:space:]]*$/ {
            print
            while ((getline line < insfile) > 0) print line
            close(insfile)
            next
        }
        { print }
    ' "$file" >"$tmp" && mv "$tmp" "$file"

    rm -f "$insert_file" || true
}

bootstrap_filesystem() {
    # Clean if update
    if [[ "${UPDATE}" == "true" ]]; then
        echo "Cleaning for update..."
        rm -f "${LOGFILE}" || true
        rm -f "${DAPPNODE_CORE_DIR}"/docker-compose-*.yml || true
        rm -f "${DAPPNODE_CORE_DIR}"/dappnode_package-*.json || true
        rm -f "${DAPPNODE_CORE_DIR}"/*.tar.xz || true
        rm -f "${DAPPNODE_CORE_DIR}"/*.txz || true
        rm -f "${DAPPNODE_CORE_DIR}/.dappnode_profile" || true
        rm -f "${CONTENT_HASH_FILE}" || true
    fi

    # Create necessary directories
    mkdir -p "${DAPPNODE_DIR}"
    mkdir -p "${DAPPNODE_CORE_DIR}"
    mkdir -p "${DAPPNODE_DIR}/scripts"
    mkdir -p "${DAPPNODE_CORE_DIR}/scripts"
    mkdir -p "${DAPPNODE_DIR}/config"
    mkdir -p "${LOGS_DIR}"

    # Ensure the log file path exists before first use by helpers.
    touch "${LOGFILE}" || true
}

# Check if port 80 is in use (necessary for HTTPS)
# Returns IS_PORT_USED=true only if port 80 or 443 is used by something OTHER than our HTTPS container
is_port_used() {
    # Check if port 80 or 443 is in use at all
    local port80_used port443_used
    if command -v lsof >/dev/null 2>&1; then
        lsof -i -P -n | grep ":80 (LISTEN)" &>/dev/null && port80_used=true || port80_used=false
        lsof -i -P -n | grep ":443 (LISTEN)" &>/dev/null && port443_used=true || port443_used=false
    else
        warn "lsof not found; assuming ports 80/443 are in use (HTTPS will be skipped)"
        IS_PORT_USED=true
        return
    fi

    if [ "$port80_used" = false ] && [ "$port443_used" = false ]; then
        IS_PORT_USED=false
        return
    fi

    # If either port is in use, check if it's our HTTPS container
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^DAppNodeCore-https.dnp.dappnode.eth$"; then
        # Port 80 or 443 is used by our HTTPS container, so we consider it "not used" for package determination
        IS_PORT_USED=false
    else
        # Port 80 or 443 is used by something else
        IS_PORT_USED=true
    fi
}

# Determine packages to be installed
determine_packages() {
    # Explicit package list override from flag/env always has top priority.
    # It supersedes MINIMAL/LITE and any OS/port-based package determination.
    if [[ -n "${PACKAGES//[[:space:],]/}" ]]; then
        local raw token normalized
        local custom_pkgs=()

        raw="${PACKAGES//,/ }"
        for token in $raw; do
            normalized="$(echo "$token" | tr '[:lower:]' '[:upper:]')"
            case "$normalized" in
                HTTPS|BIND|IPFS|VPN|WIREGUARD|DAPPMANAGER|WIFI|NOTIFICATIONS|PREMIUM)
                    ;;
                *)
                    die "Unknown package in --packages/PACKAGES: '$token'. Allowed: HTTPS,BIND,IPFS,VPN,WIREGUARD,DAPPMANAGER,WIFI,NOTIFICATIONS,PREMIUM"
                    ;;
            esac

            local exists=false
            local pkg
            for pkg in "${custom_pkgs[@]}"; do
                if [[ "$pkg" == "$normalized" ]]; then
                    exists=true
                    break
                fi
            done

            if [[ "$exists" == "false" ]]; then
                custom_pkgs+=("$normalized")
            fi
        done

        [[ ${#custom_pkgs[@]} -gt 0 ]] || die "--packages/PACKAGES was provided but no valid packages were found"

        # DAPPMANAGER is required for a functional install; ensure it's present on explicit overrides.
        local has_dappmanager=false
        local pkg
        for pkg in "${custom_pkgs[@]}"; do
            if [[ "$pkg" == "DAPPMANAGER" ]]; then
                has_dappmanager=true
                break
            fi
        done
        if [[ "$has_dappmanager" == "false" ]]; then
            custom_pkgs+=("DAPPMANAGER")
            log "--packages/PACKAGES did not include DAPPMANAGER; appending it automatically"
        fi

        if [[ "${MINIMAL}" == "true" || "${LITE}" == "true" ]]; then
            log "Custom packages provided; overriding --minimal/--lite and MINIMAL/LITE"
        fi
        MINIMAL=false
        LITE=false
        PKGS=("${custom_pkgs[@]}")

        log "Packages override enabled via --packages/PACKAGES"
        log "Packages to be installed: ${PKGS[*]}"
        log "PKGS: ${PKGS[*]}"
        for comp in "${PKGS[@]}"; do
            local ver_var
            ver_var="${comp}_VERSION"
            log "$ver_var = ${!ver_var-}"
        done
        return 0
    fi

    # Global override: new minimal install, regardless of OS.
    if [[ "${MINIMAL}" == "true" ]]; then
        PKGS=(BIND DAPPMANAGER NOTIFICATIONS PREMIUM)
        log "Minimal mode enabled; overriding packages"
        log "Packages to be installed: ${PKGS[*]}"
        log "PKGS: ${PKGS[*]}"
        for comp in "${PKGS[@]}"; do
            local ver_var
            ver_var="${comp}_VERSION"
            log "$ver_var = ${!ver_var-}"
        done
        return 0
    fi

    # Global override: lite install (former minimal behavior), regardless of OS.
    if [[ "${LITE}" == "true" ]]; then
        PKGS=(BIND VPN WIREGUARD DAPPMANAGER NOTIFICATIONS PREMIUM)
        log "Lite mode enabled; overriding packages"
        log "Packages to be installed: ${PKGS[*]}"
        log "PKGS: ${PKGS[*]}"
        for comp in "${PKGS[@]}"; do
            local ver_var
            ver_var="${comp}_VERSION"
            log "$ver_var = ${!ver_var-}"
        done
        return 0
    fi

    # Default mode (no --packages/--minimal/--lite): install full package set.
    # HTTPS is included only when ports 80/443 are available.
    is_port_used
    if [ "$IS_PORT_USED" == "true" ]; then
        PKGS=(BIND IPFS VPN WIREGUARD DAPPMANAGER WIFI NOTIFICATIONS PREMIUM)
    else
        PKGS=(HTTPS BIND IPFS VPN WIREGUARD DAPPMANAGER WIFI NOTIFICATIONS PREMIUM)
    fi

    log "Packages to be installed: ${PKGS[*]}"

    # Debug: print all PKGS and their version variables
    log "PKGS: ${PKGS[*]}"
    for comp in "${PKGS[@]}"; do
        local ver_var
        ver_var="${comp}_VERSION"
        log "$ver_var = ${!ver_var-}"
    done
}

valid_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        return 1
    fi

    local IFS='.'
    # shellcheck disable=SC2206
    local octets=( $ip )
    [[ ${#octets[@]} -eq 4 ]] || return 1
    [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]
}

configure_static_ip() {
    if [[ -z "${STATIC_IP}" ]]; then
        return 0
    fi

    if valid_ip "$STATIC_IP"; then
        echo "$STATIC_IP" >"${DAPPNODE_DIR}/config/static_ip"
    else
        die "The static IP provided (${STATIC_IP}) is not valid."
    fi
}

ensure_profile_loaded() {
    # If LOCAL_PROFILE_PATH is set, use it as the profile source instead of downloading
    if [[ -n "${LOCAL_PROFILE_PATH}" ]]; then
        log "Using local profile: ${LOCAL_PROFILE_PATH}"
        cp "$LOCAL_PROFILE_PATH" "$DAPPNODE_PROFILE"
    elif [[ ! -f "$DAPPNODE_PROFILE" ]]; then
        download_file "${DAPPNODE_PROFILE}" "${PROFILE_URL}"
    fi

    # shellcheck disable=SC1090
    source "${DAPPNODE_PROFILE}"
}

resolve_packages() {
    # The indirect variable expansion used in ${!ver##*:} allows us to use versions like 'dev:development'
    # If such variable with 'dev:'' suffix is used, then the component is built from specified branch or commit.
    # you can also specify an IPFS version like /ipfs/<cid>:<version> (the exact version is required).
    determine_packages
    for comp in "${PKGS[@]}"; do
        ver="${comp}_VERSION"
        log "Processing $comp: ${!ver-}"

        raw_version_ref="${!ver-}"
        if [[ "$raw_version_ref" == /ipfs/* || "$raw_version_ref" == ipfs/* ]]; then
            resolved_ref="$(normalize_ipfs_version_ref "$raw_version_ref" "$comp")" || exit 1
            printf -v "${comp}_VERSION" '%s' "$resolved_ref"
            raw_version_ref="$resolved_ref"
            log "Using IPFS for ${comp}: ${raw_version_ref%:*} (version ${raw_version_ref##*:})"
            DOWNLOAD_URL="${IPFS_ENDPOINT%/}${raw_version_ref%:*}"
            version_for_filenames="${raw_version_ref##*:}"
        else
            version_for_filenames="${raw_version_ref##*:}"
            DOWNLOAD_URL="https://github.com/dappnode/DNP_${comp}/releases/download/v${version_for_filenames}"
        fi
        comp_lower="$(echo "$comp" | tr '[:upper:]' '[:lower:]')"
        printf -v "${comp}_URL" '%s' "${DOWNLOAD_URL}/${comp_lower}.dnp.dappnode.eth_${version_for_filenames}_linux-${ARCH}.txz"
        printf -v "${comp}_YML" '%s' "${DOWNLOAD_URL}/docker-compose.yml"
        printf -v "${comp}_MANIFEST" '%s' "${DOWNLOAD_URL}/dappnode_package.json"
        printf -v "${comp}_YML_FILE" '%s' "${DAPPNODE_CORE_DIR}/docker-compose-${comp_lower}.yml"
        printf -v "${comp}_FILE" '%s' "${DAPPNODE_CORE_DIR}/${comp_lower}.dnp.dappnode.eth_${version_for_filenames}_linux-${ARCH}.txz"
        printf -v "${comp}_MANIFEST_FILE" '%s' "${DAPPNODE_CORE_DIR}/dappnode_package-${comp_lower}.json"
    done
}

dappnode_core_build() {
    for comp in "${PKGS[@]}"; do
        ver="${comp}_VERSION"
        if [[ ${!ver} == dev:* ]]; then
            if $IS_MACOS; then
                echo "Development builds (dev:*) are not supported on macOS."
                exit 1
            fi
            echo "Cloning & building DNP_${comp}..."
            if ! dpkg -s git >/dev/null 2>&1; then
                apt-get install -y git
            fi
            local tmpdir
            tmpdir="$(mktemp -d)"
            pushd "$tmpdir" >/dev/null || {
                echo "Error on pushd"
                exit 1
            }
            git clone -b "${!ver##*:}" https://github.com/dappnode/DNP_"${comp}"
            # Change version in YAML to the custom one
            local docker_ver comp_lower
            docker_ver="$(echo "${!ver##*:}" | sed 's/\//_/g')"
            comp_lower="$(echo "$comp" | tr '[:upper:]' '[:lower:]')"
            sed_inplace "s~^\(\s*image\s*:\s*\).*~\1${comp_lower}.dnp.dappnode.eth:${docker_ver}~" "DNP_${comp}/docker-compose.yml"
            docker compose -f ./DNP_"${comp}"/docker-compose.yml build
            cp "./DNP_${comp}/docker-compose.yml" "${DAPPNODE_CORE_DIR}/docker-compose-${comp_lower}.yml"
            cp "./DNP_${comp}/dappnode_package.json" "${DAPPNODE_CORE_DIR}/dappnode_package-${comp_lower}.json"
            rm -rf "./DNP_${comp}"
            popd >/dev/null || {
                echo "Error on popd"
                exit 1
            }
            rm -rf "$tmpdir"
        fi
    done
}

dappnode_core_download() {
    for comp in "${PKGS[@]}"; do
        ver="${comp}_VERSION"
        if [[ ${!ver} != dev:* ]]; then
            local file_var="${comp}_FILE"
            local url_var="${comp}_URL"
            local yml_file_var="${comp}_YML_FILE"
            local yml_var="${comp}_YML"
            local manifest_file_var="${comp}_MANIFEST_FILE"
            local manifest_var="${comp}_MANIFEST"

            # Download DAppNode Core Images if needed
            echo "Downloading ${comp} tar..."
            [ -f "${!file_var}" ] || download_file "${!file_var}" "${!url_var}" || exit 1
            # Download DAppNode Core docker-compose yml files if needed
            echo "Downloading ${comp} yml..."
            [ -f "${!yml_file_var}" ] || download_file "${!yml_file_var}" "${!yml_var}" || exit 1
            # Download DAppNode Core manifest files if needed
            echo "Downloading ${comp} manifest..."
            [ -f "${!manifest_file_var}" ] || download_file "${!manifest_file_var}" "${!manifest_var}" || exit 1

            # macOS: patch compose files for Docker Desktop compatibility
            if $IS_MACOS; then
                remove_logging_section "${!yml_file_var}"
                patch_compose_paths "${!yml_file_var}"
                # Inject macOS-specific env vars into the dappmanager compose
                if [[ "$comp" == "DAPPMANAGER" ]]; then
                    patch_dappmanager_compose_for_macos "${!yml_file_var}"
                fi
            fi
        fi
    done
}

dappnode_core_load() {
    for comp in "${PKGS[@]}"; do
        ver="${comp}_VERSION"
        if [[ ${!ver} != dev:* ]]; then
            local comp_lower image file_var
            comp_lower="$(echo "$comp" | tr '[:upper:]' '[:lower:]')"
            image="${comp_lower}.dnp.dappnode.eth:${!ver##*:}"
            file_var="${comp}_FILE"
            if [[ -z "$(docker images -q "$image" 2>/dev/null)" ]]; then
                docker load -i "${!file_var}" 2>&1 | tee -a "$LOGFILE"
            fi
        fi
    done
}

customMotd() {
    generateMotdText

    if [ -d "${UPDATE_MOTD_DIR}" ]; then
        # Ubuntu configuration
        modifyMotdGeneration
    fi
}

# Debian distros use /etc/motd plain text file
generateMotdText() {
    local welcome_message

    # Check and create the MOTD file if it does not exist
    if [ ! -f "${MOTD_FILE}" ]; then
        touch "${MOTD_FILE}"
    fi

    # Write the ASCII art and welcome message as plain text
    cat <<'EOF' >"${MOTD_FILE}"
  ___                              _     
 |   \ __ _ _ __ _ __ _ _  ___  __| |___ 
 | |) / _` | '_ \ '_ \ ' \/ _ \/ _` / -_)
 |___/\__,_| .__/ .__/_||_\___/\__,_\___|
           |_|  |_|                      
EOF
    welcome_message="\nChoose a way to connect to your DAppNode, then go to http://my.dappnode\n\n- Wifi\t\tScan and connect to DAppNodeWIFI. Get wifi credentials with dappnode_wifi\n\n- Local Proxy\tConnect to the same router as your DAppNode. Then go to http://dappnode.local\n\n- Wireguard\tDownload Wireguard app on your device. Get your dappnode wireguard credentials with dappnode_wireguard\n\n- Open VPN\tDownload Open VPN app on your device. Get your openVPN creds with dappnode_openvpn\n\n\nTo see a full list of commands available execute dappnode_help\n"
    printf "%b" "$welcome_message" >>"${MOTD_FILE}"
}

# Ubuntu distros use /etc/update-motd.d/ to generate the motd
modifyMotdGeneration() {
    local disabled_motd_dir
    disabled_motd_dir="${UPDATE_MOTD_DIR}/disabled"

    mkdir -p "${disabled_motd_dir}"

    # Move all the files in /etc/update-motd.d/ to /etc/update-motd.d/disabled/
    # Except for the files listed in "files_to_keep"
    files_to_keep="00-header 50-landscape-sysinfo 98-reboot-required"
    local file base_file
    for file in "${UPDATE_MOTD_DIR}"/*; do
        base_file="$(basename "${file}")"
        if [ -f "${file}" ] && ! echo "${files_to_keep}" | grep -qw "${base_file}"; then
            mv "${file}" "${disabled_motd_dir}/"
        fi
    done
}

addSwap() {
    # Is swap enabled?
    IS_SWAP=$(swapon --show | wc -l)

    # if not then create it
    if [ "$IS_SWAP" -eq 0 ]; then
        echo 'Swap not found. Adding swapfile.'
        #RAM=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        #SWAP=$(($RAM * 2))
        SWAP=8388608
        fallocate -l "${SWAP}k" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap defaults 0 0' >>/etc/fstab
    else
        echo 'Swap found. No changes made.'
    fi
}

# Add .dappnode_profile sourcing to the user's default shell configuration
add_profile_to_shell() {
    local user_home
    local shell_configs

    if $IS_MACOS; then
        user_home="$HOME"
        # macOS defaults to zsh, but some users still run bash.
        shell_configs=(".zshrc" ".zprofile" ".bashrc" ".bash_profile")
    else
        # Linux: determine user home from /etc/passwd
        local user_name
        user_name=$(grep 1000 /etc/passwd | cut -f 1 -d:)
        if [ -n "$user_name" ]; then
            user_home="/home/$user_name"
        else
            user_home="/root"
        fi
        shell_configs=(".profile" ".bashrc")
    fi

    for config_file in "${shell_configs[@]}"; do
        local config_path="${user_home}/${config_file}"
        local source_line

        # .profile may be evaluated by /bin/sh (dash on Debian/Ubuntu) where `source` is not valid.
        # Use POSIX '.' there; use `source` elsewhere (bash/zsh).
        if [ "$config_file" = ".profile" ]; then
            source_line="[ -f \"${DAPPNODE_PROFILE}\" ] && . \"${DAPPNODE_PROFILE}\""
        else
            source_line="[ -f \"${DAPPNODE_PROFILE}\" ] && source \"${DAPPNODE_PROFILE}\""
        fi

        # Create config file if it doesn't exist
        [ ! -f "$config_path" ] && touch "$config_path"
        # Add profile sourcing if not already present
        if ! grep -q "${DAPPNODE_PROFILE}" "$config_path"; then
            echo "########          DAPPNODE PROFILE          ########" >> "$config_path"
            echo "$source_line" >> "$config_path"
            echo "" >> "$config_path"
        fi
    done
}

dappnode_core_start() {
    echo "DAppNode starting..." 2>&1 | tee -a "$LOGFILE"

    if [[ ${#DNCORE_COMPOSE_ARGS[@]} -eq 0 ]]; then
        build_dncore_compose_args
    fi
    [[ ${#DNCORE_COMPOSE_ARGS[@]} -gt 0 ]] || die "No docker-compose-*.yml files found in ${DAPPNODE_CORE_DIR}"

    docker compose "${DNCORE_COMPOSE_ARGS[@]}" up -d 2>&1 | tee -a "$LOGFILE"
    echo "DAppNode started" 2>&1 | tee -a "$LOGFILE"

    # Add profile sourcing to user's shell configuration
    add_profile_to_shell

    # Remove return from profile so it can be sourced in login shells
    sed_inplace '/return/d' "$DAPPNODE_PROFILE"

    # Download access_credentials script
    [ -f "$DAPPNODE_ACCESS_CREDENTIALS" ] || download_file "${DAPPNODE_ACCESS_CREDENTIALS}" "${DAPPNODE_ACCESS_CREDENTIALS_URL}"

    # Linux-only: clean up rc.local
    if $IS_LINUX; then
        if [ -f "/etc/rc.local" ] && [ ! -f "${DAPPNODE_DIR}/.firstboot" ]; then
            sed_inplace '/\/usr\/src\/dappnode\/scripts\/dappnode_install.sh/d' /etc/rc.local 2>&1 | tee -a "$LOGFILE"
        fi
    fi

    # Display help message to the user
    echo "Execute dappnode_help to see a full list with commands available"
}

grabContentHashes() {
    if [ ! -f "${CONTENT_HASH_FILE}" ]; then
        local content_hash_pkgs=(geth besu nethermind erigon prysm teku lighthouse nimbus lodestar)
        for comp in "${content_hash_pkgs[@]}"; do
            CONTENT_HASH=$(download_stdout "https://github.com/dappnode/DAppNodePackage-${comp}/releases/latest/download/content-hash")
            if [ -z "$CONTENT_HASH" ]; then
                echo "ERROR! Failed to find content hash of ${comp}." 2>&1 | tee -a "$LOGFILE"
                exit 1
            fi
            echo "${comp}.dnp.dappnode.eth,${CONTENT_HASH}" >>"${CONTENT_HASH_FILE}"
        done
    fi
}

# /sgx will only be installed on ISO's dappnode not on standalone script
installSgx() {
    if [ -d "/usr/src/dappnode/iso/sgx" ]; then
        # from sgx_linux_x64_driver_2.5.0_2605efa.bin
        /usr/src/dappnode/iso/sgx/sgx_linux_x64_driver.bin 2>&1 | tee -a "$LOGFILE"
        /usr/src/dappnode/iso/sgx/enable_sgx 2>&1 | tee -a "$LOGFILE"
    fi
}

# /extra_dpkg will only be installed on ISO's dappnode not on standalone script
installExtraDpkg() {
    if [ -d "/usr/src/dappnode/iso/extra_dpkg" ]; then
        dpkg -i /usr/src/dappnode/iso/extra_dpkg/*.deb 2>&1 | tee -a "$LOGFILE"
    fi
}

# The main user needs to be added to the docker group to be able to run docker commands without sudo
# Explained in: https://docs.docker.com/engine/install/linux-postinstall/
addUserToDockerGroup() {
    # UID is provided to the first regular user created in the system
    local user
    user=$(grep 1000 "/etc/passwd" | cut -f 1 -d:)

    # If USER is not found, warn the user and return
    if [ -z "$user" ]; then
        echo "WARN: Default user not found. Could not add it to the docker group." 2>&1 | tee -a "$LOGFILE"
        return
    fi

    if groups "$user" | grep &>/dev/null '\bdocker\b'; then
        echo "User $user is already in the docker group" 2>&1 | tee -a "$LOGFILE"
        return
    fi

    # This step is already done in the dappnode_install_pre.sh script,
    # but it's not working in the Ubuntu ISO because the late-commands in the autoinstall.yaml
    # file are executed before the user is created.
    usermod -aG docker "$user"
    echo "User $user added to the docker group" 2>&1 | tee -a "$LOGFILE"
}

##############################################
####             SCRIPT START             ####
##############################################

main() {
    parse_args "$@"
    validate_install_mode

    bootstrap_filesystem
    check_prereqs
    configure_static_ip
    ensure_profile_loaded
    resolve_packages

    echo "" 2>&1 | tee -a "$LOGFILE"
    echo "##############################################" 2>&1 | tee -a "$LOGFILE"
    echo "####          DAPPNODE INSTALLER          ####" 2>&1 | tee -a "$LOGFILE"
    echo "##############################################" 2>&1 | tee -a "$LOGFILE"

    # --- Linux-only setup steps ---
    if $IS_LINUX; then
        if [[ "${MINIMAL}" != "true" && "${LITE}" != "true" ]]; then
            echo "Creating swap memory..." 2>&1 | tee -a "$LOGFILE"
            addSwap

            echo "Customizing login..." 2>&1 | tee -a "$LOGFILE"
            customMotd

            echo "Installing extra packages..." 2>&1 | tee -a "$LOGFILE"
            installExtraDpkg

            echo "Grabbing latest content hashes..." 2>&1 | tee -a "$LOGFILE"
            grabContentHashes

            if [ "$ARCH" == "amd64" ]; then
            echo "Installing SGX modules..." 2>&1 | tee -a "$LOGFILE"
            installSgx

            echo "Installing extra packages..." 2>&1 | tee -a "$LOGFILE"
            installExtraDpkg # TODO: Why is this being called twice?
        fi
    fi

        echo "Adding user to docker group..." 2>&1 | tee -a "$LOGFILE"
        addUserToDockerGroup
    fi

    # --- Common steps (Linux and macOS) ---
    echo "Creating dncore_network if needed..." 2>&1 | tee -a "$LOGFILE"
    docker network create --driver bridge --subnet 172.33.0.0/16 dncore_network 2>&1 | tee -a "$LOGFILE" || true

    echo "Building DAppNode Core if needed..." 2>&1 | tee -a "$LOGFILE"
    dappnode_core_build

    echo "Downloading DAppNode Core..." 2>&1 | tee -a "$LOGFILE"
    dappnode_core_download

    # Build compose args now that compose files exist
    build_dncore_compose_args

    echo "Loading DAppNode Core..." 2>&1 | tee -a "$LOGFILE"
    dappnode_core_load

    # --- Start DAppNode ---
    if $IS_LINUX; then
        if [ ! -f "${DAPPNODE_DIR}/.firstboot" ]; then
            echo "DAppNode installed" 2>&1 | tee -a "$LOGFILE"
            dappnode_core_start
            print_vpn_access_credentials
        fi

        # Run test in interactive terminal (first boot only)
        if [ -f "${DAPPNODE_DIR}/.firstboot" ]; then
            apt-get update
            apt-get install -y kbd
            openvt -s -w -- sudo -u root "${DAPPNODE_DIR}/scripts/dappnode_test_install.sh"
            exit 0
        fi
    fi

    if $IS_MACOS; then
        echo "DAppNode installed" 2>&1 | tee -a "$LOGFILE"
        dappnode_core_start
        print_vpn_access_credentials
    fi
}

main "$@"
