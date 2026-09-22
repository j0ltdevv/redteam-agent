#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")" || exit 1
CONF_SRC="$SCRIPT_DIR/nftables-opsec.conf"
CONF_DST="/etc/nftables.d/opencode-opsec.conf"
LOG_FILE="/var/log/opencode-nftables.log"

if [ "$(id -u)" != "0" ]
then
    echo "nftables-apply: must run as root (no sudo in agent, human applies manually)" >&2
    exit 1
fi

if [ ! -f "$CONF_SRC" ]
then
    echo "nftables-apply: source conf not found at $CONF_SRC" >&2
    exit 1
fi

mkdir -p "$(dirname "$CONF_DST")" || exit 1
cp "$CONF_SRC" "$CONF_DST" || exit 1

if nft -f "$CONF_DST" >> "$LOG_FILE" 2>&1
then
    echo "nftables-apply: ruleset applied from $CONF_DST" >> "$LOG_FILE" || exit 1
    echo "nftables-apply: OK rules applied"
    exit 0
else
    echo "nftables-apply: FAILED to apply $CONF_DST see $LOG_FILE" >&2
    exit 1
fi
