#!/usr/bin/env bash
# lib/roe_gate.sh — source unique du garde ROE (fail-closed, centralise).
# P1 #2 (2026-09-27) : centralise l'autorisation scope.json (hostname + scope[]
# + ips[]/domains[]/cidrs[]/outOfScope[]). Sourcé par dispatcher.sh, browser_flow.py,
# mcp_*.sh, egress-wrap.sh. Aucun side-effect au chargement.
_ROE_GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$_ROE_GATE_DIR/scope.sh" 2>/dev/null || true
# shellcheck source=/dev/null
. "$_ROE_GATE_DIR/loopback_scope.sh" 2>/dev/null || true

_roe_is_loopback() {
    local h="${1:-}"
    case "${h,,}" in
        localhost|127.0.0.1|0.0.0.0|::1|"[::1]"|host.docker.internal) return 0 ;;
        127.*) return 0 ;;
    esac
    return 1
}
_roe_is_ipv4() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }
_roe_is_cidr() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]; }
_roe_ip_in_cidr() {
    local ip="$1" cidr="$2"
    python3 - "$ip" "$cidr" <<'PY' 2>/dev/null
import ipaddress, sys
try:
    ip = ipaddress.ip_address(sys.argv[1])
    net = ipaddress.ip_network(sys.argv[2], strict=False)
    raise SystemExit(0 if ip in net else 1)
except Exception:
    raise SystemExit(1)
PY
}
_roe_hostname_matches() {
    local cand="${1,,}" pat="${2,,}"
    cand="${cand#[}"; cand="${cand%]}"
    pat="${pat#[}"; pat="${pat%]}"
    [[ -n "$cand" && -n "$pat" ]] || return 1
    if [[ "$cand" == "$pat" ]]; then return 0; fi
    if [[ "$pat" == "*."* ]]; then
        local base="${pat#*.}"
        case "$cand" in
            *."$base"|"$base") return 0 ;;
        esac
    fi
    return 1
}
_roe_scope_entries() {
    local eng_dir="${1:?engagement dir required}"
    local scope_file="$eng_dir/scope.json"
    [[ -f "$scope_file" ]] || return 0
    jq -r '([.hostname] + (.scope // [])) | map(select(type=="string" and .!="")) | unique[]' "$scope_file" 2>/dev/null || true
    jq -r '(.ips // []) | map(select(type=="string" and .!="")) | .[]' "$scope_file" 2>/dev/null || true
    jq -r '(.domains // []) | map(select(type=="string" and .!="")) | .[]' "$scope_file" 2>/dev/null || true
    jq -r '(.cidrs // []) | map(select(type=="string" and .!="")) | .[]' "$scope_file" 2>/dev/null || true
}
_roe_is_out_of_scope() {
    local candidate="$1" eng_dir="$2"
    local scope_file="$eng_dir/scope.json"
    [[ -f "$scope_file" ]] || return 1
    local oos
    while IFS= read -r oos; do
        [[ -n "$oos" ]] || continue
        if _roe_hostname_matches "$candidate" "$oos"; then return 0; fi
        if _roe_is_ipv4 "$candidate" && _roe_is_cidr "$oos" && _roe_ip_in_cidr "$candidate" "$oos"; then return 0; fi
        if _roe_is_ipv4 "$candidate" && _roe_is_ipv4 "$oos" && [[ "$candidate" == "$oos" ]]; then return 0; fi
    done < <(jq -r '(.outOfScope // .out_of_scope // []) | map(select(type=="string" and .!="")) | .[]' "$scope_file" 2>/dev/null || true)
    return 1
}
_roe_extract_host() {
    local raw="${1:-}"
    raw="$(printf '%s' "$raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$raw" ]] || { echo ""; return 0; }
    python3 - "$raw" <<'PY' 2>/dev/null
import sys
from urllib.parse import urlsplit
raw = sys.argv[1].strip()
if '://' not in raw:
    host = raw.split('/')[0].split('?')[0].split('#')[0]
    if host.count(':') == 1 and not host.startswith('['):
        host = host.rsplit(':', 1)[0]
    print(host.strip('[]'))
    raise SystemExit(0)
parsed = urlsplit(raw if '://' in raw else f'http://{raw}')
host = parsed.hostname or ''
print(host.strip())
PY
}
rt_roe_allow_host() {
    local eng_dir="${1:?engagement dir required}"
    local host="${2:-}"
    host="$(printf '%s' "$host" | tr -d '[:space:]')"
    [[ -n "$host" ]] || return 1
    if _roe_is_out_of_scope "$host" "$eng_dir"; then return 1; fi
    if _roe_is_loopback "$host"; then return 0; fi
    local entry
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        entry="$(printf '%s' "$entry" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [[ -n "$entry" ]] || continue
        if _roe_is_cidr "$entry" && _roe_is_ipv4 "$host"; then
            if _roe_ip_in_cidr "$host" "$entry"; then return 0; fi
            continue
        fi
        if _roe_is_ipv4 "$entry" && _roe_is_ipv4 "$host"; then
            [[ "$host" == "$entry" ]] && return 0
            continue
        fi
        if _roe_hostname_matches "$host" "$entry"; then return 0; fi
    done < <(_roe_scope_entries "$eng_dir")
    return 1
}
rt_roe_allow_ip() { rt_roe_allow_host "$1" "$2"; }
rt_roe_allow_url() {
    local eng_dir="$1" url="$2"
    local host
    host="$(_roe_extract_host "$url")"
    [[ -n "$host" ]] || return 1
    rt_roe_allow_host "$eng_dir" "$host"
}
rt_roe_allow() {
    local eng_dir="${1:?engagement dir required}"
    local raw="${2:-}"
    [[ -n "$raw" ]] || return 1
    if [[ "$raw" == *"://"* ]]; then
        rt_roe_allow_url "$eng_dir" "$raw"
    else
        local host
        host="$(_roe_extract_host "$raw")"
        rt_roe_allow_host "$eng_dir" "${host:-$raw}"
    fi
}
rt_roe_check() {
    local eng_dir="${1:?engagement dir required}"
    local raw="${2:-}"
    local enforce=0
    [[ "${3:-}" == "--enforce" ]] && enforce=1
    if rt_roe_allow "$eng_dir" "$raw"; then
        return 0
    fi
    if (( enforce )); then
        echo "FATAL ROE: '$raw' hors scope.json ($eng_dir/scope.json) -- refus fail-closed." >&2
        echo "       Autorises: $(_roe_scope_entries "$eng_dir" | tr '\n' ' ')" >&2
        echo "       outOfScope: $(jq -r '(.outOfScope // .out_of_scope // []) | join(\", \")' "$eng_dir/scope.json" 2>/dev/null || echo "(aucun)")" >&2
        exit 1
    fi
    return 1
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    eng="${1:-}"
    target="${2:-}"
    flag="${3:-}"
    if [[ -z "$eng" || -z "$target" ]]; then
        echo "usage: $0 <engagement_dir> <host|ip|url> [--enforce]" >&2
        exit 2
    fi
    if [[ "$flag" == "--enforce" ]]; then
        rt_roe_check "$eng" "$target" --enforce
    else
        rt_roe_allow "$eng" "$target"
    fi
fi
