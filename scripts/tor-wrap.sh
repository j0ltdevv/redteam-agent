#!/usr/bin/env bash
# Route command through Tor SOCKS5 proxy via the redteam-tor-gateway container.
# This ensures ALL traffic from the command goes through Tor, even tools that
# ignore HTTP_PROXY/HTTPS_PROXY.
#
# Fail-closed: if neither the gateway nor a host Tor SOCKS5 is reachable,
# refuse to run the command (exit 1) unless RT_ALLOW_DIRECT=1 is set
# explicitly, in which case run direct and log a warning.
#
# Usage: tor-wrap.sh <command> [args…]
# Env: RT_ALLOW_DIRECT=1  # explicit opt-out of fail-closed (logged)
set -e

if [ "$#" -eq "0" ]
then
    echo "[tor-wrap] ERROR: usage: tor-wrap.sh <command> [args…]" >&2
    exit 2
fi

TOR_SOCKS="socks5h://127.0.0.1:9050"

route_via_tor() {
    export ALL_PROXY="$TOR_SOCKS"
    export HTTP_PROXY="$TOR_SOCKS"
    export HTTPS_PROXY="$TOR_SOCKS"
    export no_proxy="localhost,127.0.0.1,::1"
    echo "[tor-wrap] Routing through Tor ($TOR_SOCKS)" >&2
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

if gateway_up
then
    route_via_tor
    exec "$@"
fi

if host_tor_up
then
    echo "[tor-wrap] Gateway down, falling back to host Tor ($TOR_SOCKS)" >&2
    route_via_tor
    exec "$@"
fi

if [ "${RT_ALLOW_DIRECT:-0}" = "1" ]
then
    echo "[tor-wrap] WARNING: no Tor proxy available, RT_ALLOW_DIRECT=1 set, running WITHOUT Tor isolation" >&2
    exec "$@"
fi

echo "[tor-wrap] ERROR: no Tor proxy available (gateway down, no host Tor on 127.0.0.1:9050), refusing to run" >&2
echo "[tor-wrap] ERROR: start redteam-tor-gateway or host Tor, or set RT_ALLOW_DIRECT=1 explicitly to bypass" >&2
exit 1
