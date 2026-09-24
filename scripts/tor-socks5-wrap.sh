#!/usr/bin/env bash
# Route un binaire vers la sortie reseau (VPN mode).
#
# VPN-ONLY (2026-09-24) : Tor n'est plus exige. Le trafic herite de la route
# VPN hote (Windscribe, kill-switch ON). Voir tor-wrap.sh pour le contrat
# fail-closed complet (RT_USE_TOR=1 pour l'opt-in Tor historique).
# Pourquoi pas proxychains : les binaires Go (nuclei-mcp) ne passent pas par
# libc connect() -- LD_PRELOAD/proxychains est inoperant dessus.
#
# Fail-closed : si le VPN est coupe, refuse de lancer (exit 1)
# sauf RT_ALLOW_DIRECT=1 (warning logged).
#
# Usage: tor-socks5-wrap.sh <command> [args...]
# Env:   RT_ALLOW_DIRECT=1  # opt-out explicite du fail-closed (logged)
set -euo pipefail

if [ "$#" -eq "0" ]
then
    echo "[egress] ERROR: usage: tor-socks5-wrap.sh <command> [args...]" >&2
    exit 2
fi

vpn_up() {
    if command -v windscribe-cli >/dev/null 2>&1
    then
        windscribe-cli status 2>/dev/null | grep -qiE "connecte|connected" \
            && ! windscribe-cli status 2>/dev/null | grep -qiE "coupe|disconnected"
    else
        return 1
    fi
}

route_via_vpn() {
    export NO_PROXY="localhost,127.0.0.1,::1"
    export no_proxy="localhost,127.0.0.1,::1"
    echo "[egress] Routing through host VPN (kill-switch ON expected)" >&2
}

if vpn_up
then
    route_via_vpn
    exec "$@"
fi

if [ "${RT_ALLOW_DIRECT:-0}" = "1" ]
then
    echo "[egress] WARNING: VPN disconnected, RT_ALLOW_DIRECT=1 set, running WITHOUT egress isolation" >&2
    exec "$@"
fi

echo "[egress] ERROR: no VPN connection detected (windscribe-cli: disconnected), or set RT_ALLOW_DIRECT=1 explicitly to bypass" >&2
exit 1
