#!/usr/bin/env bash
# egress-wrap.sh — exécute une commande avec l'egress du mode courant.
#
# VPN (défaut)   : exec direct — le trafic suit la route par défaut de l'hôte,
#                  c.-à-d. le tunnel VPN Windscribe (kill-switch FirewallMode=Always).
# RT_USE_TOR=1   : exec via proxychains4 -f scripts/proxychains-redteam.conf
#                  (socks5 127.0.0.1:9050, proxy_dns, localnet direct).
#
# Pourquoi ce wrapper existe : les MCP osint / nmap-mcp / cve-lookup étaient
# câblés directement sur `proxychains4 -> Tor 9050`. En mode VPN ce proxy est
# mort, donc les MCP ne démarraient plus du tout. Ici le MODE décide de la
# route, la commande reste identique côté opencode.json.
#
# Fail-closed : ni VPN ni Tor disponible -> exit 1 (sauf RT_ALLOW_DIRECT=1, loggé).
#
# Usage : egress-wrap.sh <command> [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/vpn_state.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/opsec_guard.sh"

PROXYCHAINS_BIN="${PROXYCHAINS_BIN:-/usr/bin/proxychains4}"
PROXYCHAINS_CONF="${PROXYCHAINS_CONF:-$SCRIPT_DIR/proxychains-redteam.conf}"

if [ "$#" -eq 0 ]; then
    echo "[egress] ERROR: usage: egress-wrap.sh <command> [args...]" >&2
    exit 2
fi

if [ "$(rt_egress_mode)" = "tor" ]; then
    if rt_tor_up; then
        echo "[egress] Routing through Tor (proxychains $PROXYCHAINS_CONF)" >&2
        exec "$PROXYCHAINS_BIN" -q -f "$PROXYCHAINS_CONF" "$@"
    fi
    echo "[egress] ERROR: RT_USE_TOR=1 but no Tor proxy available" >&2
    exit 1
fi

if rt_vpn_up; then
    # OPSEC fail-closed : refuse si le trafic partirait en clair (mesure IP).
    rt_og_require_isolated || exit 1
    echo "[egress] Routing through host VPN (kill-switch ON expected)" >&2
    exec "$@"
fi

if rt_allow_direct; then
    rt_warn_direct
    exec "$@"
fi

rt_refuse
exit 1
