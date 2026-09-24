#!/usr/bin/env bash
# mcp_obscura.sh — lance le MCP obscura avec l'egress du mode courant.
#
# VPN (défaut)   : `obscura mcp` (aucun proxy -> route VPN hôte)
# RT_USE_TOR=1   : `obscura --proxy socks5://127.0.0.1:9050 mcp`
#
# Avant : le proxy Tor était écrit en dur dans opencode.json, donc en mode VPN
# le MCP pointait vers un proxy mort et ne démarrait plus.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/vpn_state.sh"

OBSCURA_BIN="${OBSCURA_BIN:-$HOME/.local/bin/obscura}"

if [ "$(rt_egress_mode)" = "tor" ]; then
    if ! rt_tor_up; then
        echo "[egress] ERROR: RT_USE_TOR=1 but no Tor proxy available (obscura would point at a dead proxy)" >&2
        exit 1
    fi
    exec "$OBSCURA_BIN" --proxy "socks5://127.0.0.1:9050" mcp
fi

exec "$OBSCURA_BIN" mcp
