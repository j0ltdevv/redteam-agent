#!/usr/bin/env bash
# tor-wrap.sh — lance une commande avec l'egress du mode courant.
#
# VPN-ONLY (2026-09-24) : la sortie par défaut est le VPN hôte (Windscribe,
# kill-switch FirewallMode=Always) — la commande hérite de la route par défaut.
# Tor reste disponible en opt-in : RT_USE_TOR=1 -> SOCKS5 Tor 127.0.0.1:9050.
#
# Fail-closed : si ni VPN ni Tor, refuse de lancer (exit 1) sauf RT_ALLOW_DIRECT=1
# explicite (avertissement loggé). L'état réseau vient de scripts/lib/vpn_state.sh.
#
# Usage: tor-wrap.sh <command> [args…]
# Env:   RT_ALLOW_DIRECT=1  # opt-out explicite du fail-closed (loggé)
#        RT_USE_TOR=1       # opt-in : route via Tor SOCKS5 au lieu du VPN
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/vpn_state.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/opsec_guard.sh"

if [ "$#" -eq 0 ]; then
    echo "[egress] ERROR: usage: tor-wrap.sh <command> [args…]" >&2
    exit 2
fi

if [ "$(rt_egress_mode)" = "tor" ]; then
    if rt_tor_up; then
        TOR_SOCKS="socks5h://127.0.0.1:9050"
        export ALL_PROXY="$TOR_SOCKS"
        export HTTP_PROXY="$TOR_SOCKS"
        export HTTPS_PROXY="$TOR_SOCKS"
        export no_proxy="localhost,127.0.0.1,::1"
        echo "[egress] Routing through Tor ($TOR_SOCKS)" >&2
        exec "$@"
    fi
    echo "[egress] ERROR: RT_USE_TOR=1 but no Tor proxy available" >&2
    exit 1
fi

if rt_vpn_up; then
    # OPSEC fail-closed : refuse si le trafic partirait en clair (mesure IP).
    rt_og_require_isolated || exit 1
    # Pas de proxy à injecter : la route par défaut passe déjà par le tunnel VPN.
    # On s'assure juste de ne PAS laisser traîner un proxy Tor mort.
    unset ALL_PROXY HTTP_PROXY HTTPS_PROXY all_proxy http_proxy https_proxy || true
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
