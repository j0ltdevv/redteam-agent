#!/usr/bin/env bash
# tor-socks5-wrap.sh — egress pour les binaires qui ne passent PAS par libc
# connect() (Go : nuclei-mcp, etc.) : proxychains/LD_PRELOAD est inopérant
# dessus, on ne peut agir que via les variables d'environnement proxy.
#
# VPN-ONLY (2026-09-24) : en mode VPN (défaut) aucun proxy n'est injecté — le
# binaire suit la route par défaut de l'hôte (= tunnel Windscribe).
# RT_USE_TOR=1 : injecte socks5h://127.0.0.1:9050 (comportement historique).
#
# Fail-closed : VPN coupé -> exit 1 sauf RT_ALLOW_DIRECT=1 explicite (loggé).
#
# Usage: tor-socks5-wrap.sh <command> [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/vpn_state.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/opsec_guard.sh"

if [ "$#" -eq 0 ]; then
    echo "[egress] ERROR: usage: tor-socks5-wrap.sh <command> [args...]" >&2
    exit 2
fi

if [ "$(rt_egress_mode)" = "tor" ]; then
    if rt_tor_up; then
        export ALL_PROXY="socks5h://127.0.0.1:9050"
        export HTTP_PROXY="socks5h://127.0.0.1:9050"
        export HTTPS_PROXY="socks5h://127.0.0.1:9050"
        export NO_PROXY="localhost,127.0.0.1,::1"
        export no_proxy="localhost,127.0.0.1,::1"
        echo "[egress] Routing through Tor SOCKS5 (127.0.0.1:9050)" >&2
        exec "$@"
    fi
    echo "[egress] ERROR: RT_USE_TOR=1 but no Tor proxy available" >&2
    exit 1
fi

if rt_vpn_up; then
    # OPSEC fail-closed : refuse si le trafic partirait en clair (mesure IP).
    rt_og_require_isolated || exit 1
    unset ALL_PROXY HTTP_PROXY HTTPS_PROXY all_proxy http_proxy https_proxy || true
    export NO_PROXY="localhost,127.0.0.1,::1"
    export no_proxy="localhost,127.0.0.1,::1"
    echo "[egress] Routing through host VPN (kill-switch ON expected)" >&2
    exec "$@"
fi

if rt_allow_direct; then
    rt_warn_direct
    exec "$@"
fi

rt_refuse
exit 1
