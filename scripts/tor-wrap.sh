#!/usr/bin/env bash
# Route command through the egress proxy (VPN mode).
# VPN-ONLY (2026-09-24): les scripts n'exigent plus Tor. La sortie passe par
# l'interface VPN hôte (Windscribe, kill-switch ON) — le trafic hérite
# automatiquement de la route VPN car c'est la route par défaut du système.
# Tor reste disponible en opt-in via RT_USE_TOR=1 (gateway redteam-tor-gateway).
#
# Fail-closed: si ni le VPN ni Tor (opt-in) ne sont actifs, refuse de lancer
# (exit 1) sauf RT_ALLOW_DIRECT=1 explicite (warning logged).
#
# Usage: tor-wrap.sh <command> [args…]
# Env: RT_ALLOW_DIRECT=1  # explicit opt-out of fail-closed (logged)
#      RT_USE_TOR=1       # opt-in: route via Tor SOCKS5 au lieu du VPN
set -e

if [ "$#" -eq "0" ]
then
    echo "[egress] ERROR: usage: tor-wrap.sh <command> [args…]" >&2
    exit 2
fi

vpn_up() {
    # Windscribe CLI : état connecté (le daemon tourne en user service).
    if command -v windscribe-cli >/dev/null 2>&1
    then
        windscribe-cli status 2>/dev/null | grep -qiE "connecté|connected" \
            && ! windscribe-cli status 2>/dev/null | grep -qiE "coupé|disconnected"
    else
        return 1
    fi
}

TOR_SOCKS="socks5h://127.0.0.1:9050"

route_via_tor() {
    export ALL_PROXY="$TOR_SOCKS"
    export HTTP_PROXY="$TOR_SOCKS"
    export HTTPS_PROXY="$TOR_SOCKS"
    export no_proxy="localhost,127.0.0.1,::1"
    echo "[egress] Routing through Tor ($TOR_SOCKS)" >&2
}

route_via_vpn() {
    # Pas de proxy à injecter : la route par défaut du système passe déjà par
    # le tunnel VPN (kill-switch firewall ON). On s'assure juste de ne PAS
    # forcer un proxy Tor mort qui casserait tout.
    unset ALL_PROXY HTTP_PROXY HTTPS_PROXY all_proxy http_proxy https_proxy
    export no_proxy="localhost,127.0.0.1,::1"
    echo "[egress] Routing through host VPN (kill-switch ON expected)" >&2
}

gateway_up() {
    docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^redteam-tor-gateway$"
}

host_tor_up() {
    if command -v ss >/dev/null 2>&1
    then
        ss -lnt 2>/dev/null | grep -q ":9050"
    else
        (echo > "/dev/tcp/127.0.0.1/9050") >/dev/null 2>&1
    fi
}

# Opt-in Tor explicite (comportement historique).
if [ "${RT_USE_TOR:-0}" = "1" ]
then
    if gateway_up || host_tor_up
    then
        route_via_tor
        exec "$@"
    fi
    echo "[egress] ERROR: RT_USE_TOR=1 but no Tor proxy available" >&2
    exit 1
fi

# Chemin par défaut : VPN hôte.
if vpn_up
then
    route_via_vpn
    exec "$@"
fi

if [ "${RT_ALLOW_DIRECT:-0}" = "1" ]
then
    echo "[egress] WARNING: no VPN detected, RT_ALLOW_DIRECT=1 set, running WITHOUT egress isolation" >&2
    exec "$@"
fi

echo "[egress] ERROR: no VPN connection detected (windscribe-cli: disconnected), refusing to run" >&2
echo "[egress] ERROR: connect VPN (windscribe-cli connect) or set RT_ALLOW_DIRECT=1 explicitly to bypass" >&2
exit 1
