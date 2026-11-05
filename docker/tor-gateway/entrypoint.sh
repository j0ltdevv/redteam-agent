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
  # 2026-09-29 : l'URL etait en http:// -> reponse 301 vers https://, donc le
  # probe recevait du HTML au lieu du JSON et echouait 60 fois. Tor bootstrappait
  # pourtant a 100 % a chaque cycle (492/492) avant d'etre tue par ce probe.
  # -sL : suivre la redirection. -f : echouer sur code HTTP >= 400.
  # --socks5-hostname : la resolution passe par Tor (pas de fuite DNS).
  # --max-time : une sonde bloquee ne mange pas la boucle entiere.
  if curl -sfL --max-time 10 --socks5-hostname "127.0.0.1:9050" "https://check.torproject.org/api/ip" 2>/dev/null | grep -q "\"IsTor\":true"
  then
    echo "[tor-gateway] Tor is ready."
    READY="1"
    break
  fi
  sleep 1
done

if [ "$READY" != "1" ]
then
  # Ne pas mentir : distinguer "Tor est mort" de "Tor vit mais la sonde echoue".
  # L'ancien message affirmait "did not bootstrap" alors que Tor bootstrappait.
  if kill -0 "$TOR_PID" 2>/dev/null
  then
    echo "[tor-gateway] ERROR: readiness probe failed after ${i} tries, but Tor is still running (PID $TOR_PID). Not a bootstrap failure." >&2
  else
    echo "[tor-gateway] ERROR: Tor process died before it could bootstrap." >&2
  fi
  kill "$TOR_PID" 2>/dev/null || true
  exit 1
fi

# Keep container alive
wait "$TOR_PID"
