#!/usr/bin/env bash
# Launch the isolated redteam OpenChamber through the local OpenCode v2 adapter.
set -euo pipefail

PROJECT_DIR="${REDTEAM_DIR:-$HOME/redteam-agent}"
PROFILE_DIR="$HOME/.config/opencode-redteam"
OPENCHAMBER_DATA_DIR="${OPENCHAMBER_DATA_DIR:-$HOME/.config/openchamber-redteam}"
OPENCHAMBER_HOST="${OPENCHAMBER_HOST:-127.0.0.1}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-4098}"
OPENCHAMBER_ADAPTER_PORT="${OPENCHAMBER_ADAPTER_PORT:-4099}"
OPENCHAMBER_BIN="${OPENCHAMBER_BIN:-$(command -v openchamber || true)}"
OPENCHAMBER_OPEN_BROWSER="${OPENCHAMBER_OPEN_BROWSER:-1}"
OPENCHAMBER_BROWSER_URL="${OPENCHAMBER_BROWSER_URL:-http://127.0.0.1:$OPENCHAMBER_PORT/}"
SERVICE_STATE="$PROFILE_DIR/state/opencode/service.json"
ADAPTER_SCRIPT="$PROJECT_DIR/scripts/openchamber-v2-adapter.py"
ADAPTER_LOG="$PROFILE_DIR/state/openchamber-v2-adapter.log"

fail() {
  printf '[redteam-openchamber] ERROR: %s\n' "$*" >&2
  exit 1
}

[ -x "$OPENCHAMBER_BIN" ] || fail "openchamber binary not found"
[ -f "$SERVICE_STATE" ] || fail "dedicated OpenCode service is not running: $SERVICE_STATE"
[ -f "$ADAPTER_SCRIPT" ] || fail "compatibility adapter not found: $ADAPTER_SCRIPT"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

OPENCODE_URL=$(jq -r '.url // empty' "$SERVICE_STATE")
OPENCODE_PASSWORD=$(jq -r '.password // empty' "$SERVICE_STATE")
[ -n "$OPENCODE_URL" ] || fail "dedicated OpenCode service URL is missing"
[ -n "$OPENCODE_PASSWORD" ] || fail "dedicated OpenCode service password is missing"
case "$OPENCODE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) fail "dedicated OpenCode URL must be loopback" ;;
esac

mkdir -p "$OPENCHAMBER_DATA_DIR" "$PROFILE_DIR/state"

# The password remains in the process environment only; it is never printed.
export OPENCHAMBER_DATA_DIR
export OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"
export OPENCODE_SERVER_PASSWORD="$OPENCODE_PASSWORD"
export OPENCODE_SERVICE_STATE="$SERVICE_STATE"
export OPENCODE_UPSTREAM_URL="$OPENCODE_URL"
export OPENCODE_PROJECT_DIR="$PROJECT_DIR"
export OPENCODE_ADAPTER_PORT="$OPENCHAMBER_ADAPTER_PORT"
export OPENCODE_SKIP_START=true
export OPENCODE_HOST="http://127.0.0.1:$OPENCHAMBER_ADAPTER_PORT"

if ! python3 "$ADAPTER_SCRIPT" --self-test; then
  fail "dedicated OpenCode compatibility self-test failed"
fi

printf '[redteam-openchamber] data:       %s\n' "$OPENCHAMBER_DATA_DIR"
printf '[redteam-openchamber] OpenCode:   %s\n' "$OPENCODE_URL"
printf '[redteam-openchamber] adapter:    http://127.0.0.1:%s/\n' "$OPENCHAMBER_ADAPTER_PORT"
printf '[redteam-openchamber] UI:         http://%s:%s/\n' "$OPENCHAMBER_HOST" "$OPENCHAMBER_PORT"

python3 "$ADAPTER_SCRIPT" >"$ADAPTER_LOG" 2>&1 &
ADAPTER_PID=$!
BROWSER_PID=""
cleanup() {
  if [ -n "$BROWSER_PID" ] && kill -0 "$BROWSER_PID" 2>/dev/null; then
    kill "$BROWSER_PID" 2>/dev/null || true
    wait "$BROWSER_PID" 2>/dev/null || true
  fi
  if kill -0 "$ADAPTER_PID" 2>/dev/null; then
    kill "$ADAPTER_PID" 2>/dev/null || true
    wait "$ADAPTER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Fail closed instead of killing an unrelated process that already owns 4099.
for _ in $(seq 1 30); do
  if ! kill -0 "$ADAPTER_PID" 2>/dev/null; then
    printf '[redteam-openchamber] adapter failed; see %s\n' "$ADAPTER_LOG" >&2
    exit 1
  fi
  if python3 - "$OPENCODE_HOST/api/path?directory=$PROJECT_DIR" <<'PY'
import base64
import os
import sys
import urllib.request

request = urllib.request.Request(sys.argv[1])
credentials = f"{os.environ['OPENCODE_SERVER_USERNAME']}:{os.environ['OPENCODE_SERVER_PASSWORD']}".encode()
request.add_header("Authorization", "Basic " + base64.b64encode(credentials).decode())
try:
    with urllib.request.urlopen(request, timeout=1) as response:
        raise SystemExit(0 if response.status == 200 else 1)
except Exception:
    raise SystemExit(1)
PY
  then
    break
  fi
  sleep 0.2
done

if ! kill -0 "$ADAPTER_PID" 2>/dev/null; then
  fail "adapter exited before readiness"
fi

open_ui_when_ready() {
  local ui_url="$1"
  for _ in $(seq 1 50); do
    if curl -fsS --max-time 1 "$ui_url" >/dev/null 2>&1; then
      xdg-open "$ui_url" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.2
  done
  return 1
}

# OpenChamber serves the UI in the foreground; open its local page once ready.
if [ "$OPENCHAMBER_OPEN_BROWSER" = "1" ] && command -v xdg-open >/dev/null 2>&1; then
  open_ui_when_ready "$OPENCHAMBER_BROWSER_URL" &
  BROWSER_PID=$!
fi

# Keep OpenChamber in the foreground; the EXIT trap owns only our adapter PID.
"$OPENCHAMBER_BIN" serve --foreground --port "$OPENCHAMBER_PORT" --host "$OPENCHAMBER_HOST"
