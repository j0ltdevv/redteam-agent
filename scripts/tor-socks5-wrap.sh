#!/usr/bin/env bash
# Route un binaire vers le SOCKS5 Tor via env HTTP(S)_PROXY.
#
# Pourquoi pas proxychains : les binaires Go (nuclei-mcp) ne passent pas par
# libc connect() — LD_PRELOAD/proxychains est inopérant dessus. Le seul levier
# fiable est HTTP_PROXY/HTTPS_PROXY (scheme "socks5" supporté par net/http,
# résolution DNS distante faite par le dialer socks côté proxy).
#
# Fail-closed (même contrat que tor-wrap.sh) : si 127.0.0.1:9050 est injoignable,
# refuse de lancer (exit 1) sauf RT_ALLOW_DIRECT=1 (warning logged).
#
# Usage: tor-socks5-wrap.sh <command> [args…]
# Env:   RT_ALLOW_DIRECT=1  # opt-out explicite du fail-closed (logged)
set -euo pipefail

if [ "$#" -eq "0" ]
then
    echo "[tor-socks5-wrap] ERROR: usage: tor-socks5-wrap.sh <command> [args…]" >&2
    exit 2
fi

# socks5:// pour Go (HTTP(S)_PROXY) ; socks5h:// pour ALL_PROXY (curl et
# compagnie résolvent en local sinon = fuite DNS).
SOCKS5="socks5://127.0.0.1:9050"
SOCKS5H="socks5h://127.0.0.1:9050"

socks_up() {
    # Test de connectivité réel (le port doit accepter la connexion).
    (exec 3<>"/dev/tcp/127.0.0.1/9050") >/dev/null 2>&1
}

route_via_tor() {
    export HTTP_PROXY="$SOCKS5"
    export HTTPS_PROXY="$SOCKS5"
    export http_proxy="$SOCKS5"
    export https_proxy="$SOCKS5"
    export ALL_PROXY="$SOCKS5H"
    export all_proxy="$SOCKS5H"
    export NO_PROXY="localhost,127.0.0.1,::1"
    export no_proxy="localhost,127.0.0.1,::1"
    echo "[tor-socks5-wrap] Routing through Tor ($SOCKS5)" >&2
}

if socks_up
then
    route_via_tor
    exec "$@"
fi

if [ "${RT_ALLOW_DIRECT:-0}" = "1" ]
then
    echo "[tor-socks5-wrap] WARNING: Tor SOCKS5 unreachable on 127.0.0.1:9050, RT_ALLOW_DIRECT=1 set, running WITHOUT Tor isolation" >&2
    exec "$@"
fi

echo "[tor-socks5-wrap] ERROR: Tor SOCKS5 unreachable on 127.0.0.1:9050 (start redteam-tor-gateway: docker compose up -d tor-gateway), or set RT_ALLOW_DIRECT=1 explicitly to bypass" >&2
exit 1
