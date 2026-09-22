#!/usr/bin/env bash
# Route command through Tor SOCKS5 proxy via the redteam-tor-gateway container.
# This ensures ALL traffic from the command goes through Tor, even tools that
# ignore HTTP_PROXY/HTTPS_PROXY.
#
# Usage: tor-wrap.sh <command> [args…]
set -e

# If the tor-gateway container is running, route through it.
# Otherwise, fall back to the host's Tor SOCKS5 (if available).
if docker ps --format '{{.Names}}' | grep -q "^redteam-tor-gateway$"; then
    export ALL_PROXY="socks5h://127.0.0.1:9050"
    export HTTP_PROXY="$ALL_PROXY"
    export HTTPS_PROXY="$ALL_PROXY"
    export no_proxy="localhost,127.0.0.1,::1"
else
    # Fallback: use host Tor if available
    if ss -lnt | grep -q ':9050'; then
        export ALL_PROXY="socks5h://127.0.0.1:9050"
        export HTTP_PROXY="$ALL_PROXY"
        export HTTPS_PROXY="$ALL_PROXY"
        export no_proxy="localhost,127.0.0.1,::1"
    else
        echo "[tor-wrap] WARNING: Neither redteam-tor-gateway container nor host Tor is available." >&2
        echo "[tor-wrap] Traffic will NOT be routed through Tor." >&2
    fi
fi

exec "$@"
