#!/usr/bin/env bash
# mcp_playwright.sh — lance le MCP playwright avec l'egress du mode courant.
#
# VPN (défaut)   : `npx -y @playwright/mcp` (aucun proxy -> route VPN hôte),
#                  localhost/RFC1918 restent joignables (lab local).
# RT_USE_TOR=1   : ajoute --proxy-server socks5://127.0.0.1:9050 + --proxy-bypass
#                  (équivalent localnet de proxychains-redteam.conf).
#
# Avant : le proxy Tor était écrit en dur dans opencode.json, donc en mode VPN
# le navigateur headless sortait par un proxy mort (toute page échouait).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/vpn_state.sh"

if [ "$(rt_egress_mode)" = "tor" ]; then
    if ! rt_tor_up; then
        echo "[egress] ERROR: RT_USE_TOR=1 but no Tor proxy available (playwright would point at a dead proxy)" >&2
        exit 1
    fi
    exec npx -y @playwright/mcp \
        --proxy-server "socks5://127.0.0.1:9050" \
        --proxy-bypass "localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
fi

exec npx -y @playwright/mcp
