#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
# Load only this function; sourcing the installer itself is deliberately forbidden.
eval "$(awk '/^ensure_dncore_network\(\)/,/^}/' scripts/dappnode_install.sh)"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
LOGFILE="$test_dir/log"
calls="$test_dir/calls"
log() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >> "$test_dir/warnings"; }
docker() {
    printf '%s\n' "$*" >> "$calls"
    if [[ "$*" == "network inspect dncore_network" ]]; then [[ "$mode" != fresh ]];
    elif [[ "$*" == "network inspect --format"* ]]; then printf '%s\n' "$mock_pool";
    elif [[ "$*" == "network create"* ]]; then return "${create_exit:-0}";
    else return 2; fi
}
mode=fresh
ensure_dncore_network
grep -q -- '--gateway 172.33.0.1 --ip-range 172.33.128.0/17 dncore_network' "$calls"
mode=existing; mock_pool=172.33.128.0/17
: > "$calls"
ensure_dncore_network
! grep -q 'network create' "$calls"
[[ ! -f "$test_dir/warnings" ]]
mock_pool=
ensure_dncore_network
grep -q 'journal\|migrate-docker-networks.sh plan' "$test_dir/warnings"
! grep -q 'network create\|network rm\|network disconnect' "$calls"
mode=fresh; create_exit=1
if ensure_dncore_network; then echo 'Creation failures must propagate' >&2; exit 1; fi
echo 'PASS: fresh pool, existing pool, non-disruptive legacy notice, creation failure'
