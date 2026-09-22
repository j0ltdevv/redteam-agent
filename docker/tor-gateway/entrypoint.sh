#!/bin/sh
set -e

# Start Tor in background
tor &
TOR_PID=$!

# Wait for Tor to be ready (SOCKS port open)
echo "[tor-gateway] Waiting for Tor to bootstrap..."
for i in $(seq 1 60); do
  if curl -s --socks5 127.0.0.1:9050 http://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; then
    echo "[tor-gateway] Tor is ready."
    break
  fi
  sleep 1
done

# Keep container alive
wait $TOR_PID
