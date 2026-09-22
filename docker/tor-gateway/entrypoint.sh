#!/bin/sh
# tor-gateway entrypoint: start Tor, wait for bootstrap, fail fast otherwise.
# DNS stays on loopback (127.0.0.1:5353 per torrc). Client-side loopback
# bypass (no_proxy) is handled in scripts/tor-wrap.sh. No compose change here.
set -e

# Start Tor in background
tor &
TOR_PID="$!"

# Wait for Tor to be ready (SOCKS port open)
echo "[tor-gateway] Waiting for Tor to bootstrap..."
READY="0"
for i in $(seq 1 60)
do
  if curl -s --socks5 "127.0.0.1:9050" "http://check.torproject.org/api/ip" 2>/dev/null | grep -q "\"IsTor\":true"
  then
    echo "[tor-gateway] Tor is ready."
    READY="1"
    break
  fi
  sleep 1
done

if [ "$READY" != "1" ]
then
  echo "[tor-gateway] ERROR: Tor did not bootstrap in time, exiting." >&2
  kill "$TOR_PID" 2>/dev/null || echo "[tor-gateway] Tor process already gone" >&2
  exit 1
fi

# Keep container alive
wait "$TOR_PID"
