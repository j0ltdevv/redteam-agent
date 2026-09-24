#!/usr/bin/env bash
# Launch the isolated official OpenCode Desktop instance for redteam-agent.
#
# This launcher intentionally does not pass a Desktop path argument: the
# packaged Electron app does not consume that flag. The project is selected
# inside the dedicated Desktop userData on first launch, or with the project's
# normal UI flow.
set -euo pipefail

PROJECT_DIR="${REDTEAM_DIR:-$HOME/redteam-agent}"
PROFILE_DIR="$HOME/.config/opencode-redteam"
CONFIG_DIR="$PROFILE_DIR/config"
XDG_CONFIG_DIR="$PROFILE_DIR/config-xdg"
DATA_DIR="$PROFILE_DIR/data"
STATE_DIR="$PROFILE_DIR/state"
CACHE_DIR="$PROFILE_DIR/cache"
ENV_FILE="$PROJECT_DIR/.env"

fail() {
  printf '[redteam-desktop] ERROR: %s\n' "$*" >&2
  exit 1
}

[ -d "$PROJECT_DIR" ] || fail "project directory not found: $PROJECT_DIR"
[ -f "$ENV_FILE" ] || fail "environment file not found: $ENV_FILE"

mkdir -p "$CONFIG_DIR" "$XDG_CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$CACHE_DIR"

# Export provider credentials and MSF_* variables before Electron starts its
# OpenCode service. Do not print the environment file contents.
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# Resolve the installed Desktop package without hardcoding a version directory.
# A custom path can still be supplied explicitly for testing or packaging.
if [ -n "${OPENCODE_DESKTOP_BIN:-}" ]; then
  DESKTOP_BIN="$OPENCODE_DESKTOP_BIN"
else
  DESKTOP_BIN=$(find "$HOME/.opencode-v2/desktop" \
    -type f -name 'ai.opencode.desktop' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -n 1 | cut -d' ' -f2-)
fi

[ -n "$DESKTOP_BIN" ] || fail "no ai.opencode.desktop found below $HOME/.opencode-v2/desktop"
[ -x "$DESKTOP_BIN" ] || fail "Desktop binary is not executable: $DESKTOP_BIN"

# Isolate Electron userData/state/cache and the OpenCode server configuration,
# sessions database, and project config discovery from the daily instance.
export XDG_CONFIG_HOME="$XDG_CONFIG_DIR"
export XDG_DATA_HOME="$DATA_DIR"
export XDG_STATE_HOME="$STATE_DIR"
export XDG_CACHE_HOME="$CACHE_DIR"
export OPENCODE_CONFIG_DIR="$CONFIG_DIR"
export OPENCODE_DB="$DATA_DIR/opencode.db"
export OPENCODE_CONFIG_PROJECT_DISABLE=true

cd "$PROJECT_DIR"

printf '[redteam-desktop] project:  %s\n' "$PROJECT_DIR"
printf '[redteam-desktop] profile:  %s\n' "$PROFILE_DIR"
printf '[redteam-desktop] binary:   %s\n' "$DESKTOP_BIN"
printf '[redteam-desktop] database: %s\n' "$OPENCODE_DB"
printf '[redteam-desktop] MCP vars: loaded from %s\n' "$ENV_FILE"

# No Desktop path argument: the dedicated userData owns the selected project
# state and the OpenCode server owns the redteam config. Disable GPU because
# the v2.0.14 Wayland/Vulkan combination can crash this packaged renderer.
exec "$DESKTOP_BIN" --disable-gpu
