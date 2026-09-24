#!/usr/bin/env bash
set -euo pipefail

# operator_status.sh — the ONE state snapshot command for the operator loop.
#
# Replaces the hand-rolled state reads that used to be spread over every turn:
# `cat scope.json | jq`, `dispatcher.sh ... stats-by-stage`, `ls .auth-respawn-required`,
# `ls .osint-respawn-required`, `grep -c '^## \[FINDING' findings.md`, plus the
# intel_changed_check hook. On the 2026-09-23-235052-172-20-0-2 engagement those
# added up to ~60 shell round-trips inside a single 59-minute run.
#
# Every value the operator needs to ASSESS STATE comes back in one call:
#   scope phase/status + elapsed, stage tallies, in-flight agents, respawn flags,
#   finding count, open graph intents, and the stop-lock state.
#
# It also counts how often it has been called in the current phase and prints a
# POLL_WARNING past the budget (REDTEAM_STATUS_MAX_PER_PHASE, default 3) — so a
# polling loop is visible in the transcript instead of silently burning context.
#
# Usage:
#   operator_status.sh [engagement_dir] [--reset-counter]
#
# Call it once per phase. Do NOT call it again "to be sure".

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/engagement.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/engagement_lock.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/poll_guard.sh"

ENG_DIR_ARG=""
RESET_COUNTER=0
while (($# > 0)); do
    case "$1" in
        --reset-counter) RESET_COUNTER=1; shift ;;
        -h|--help)
            sed -n '4,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
            exit 0
            ;;
        -*) echo "unknown flag: $1" >&2; exit 1 ;;
        *)  ENG_DIR_ARG="$1"; shift ;;
    esac
done

if [[ -n "$ENG_DIR_ARG" ]]; then
    ENG_DIR="$(canonicalize_engagement_dir "$(pwd)" "$ENG_DIR_ARG" 2>/dev/null || true)"
    [[ -n "$ENG_DIR" ]] || { echo "engagement directory not found: $ENG_DIR_ARG" >&2; exit 1; }
else
    ENG_DIR="$(resolve_engagement_dir "$(pwd)" || true)"
fi
[[ -n "$ENG_DIR" ]] || { echo "no engagement directory could be resolved" >&2; exit 1; }

SCOPE="$ENG_DIR/scope.json"
CASES_DB="$ENG_DIR/cases.db"
FINDINGS="$ENG_DIR/findings.md"
GRAPH="$ENG_DIR/graph.json"

((RESET_COUNTER)) && reset_state_reads "$ENG_DIR"

sql() {
    [[ -f "$CASES_DB" ]] || return 0
    sqlite3 "$CASES_DB" ".timeout 5000" "$1" 2>/dev/null || true
}

jqget() {
    # jqget <file> <filter> <default>
    [[ -f "$1" ]] || { printf '%s\n' "$3"; return 0; }
    jq -r "$2" "$1" 2>/dev/null || printf '%s\n' "$3"
}

PHASE="$(jqget "$SCOPE" '.current_phase // "unknown"' unknown)"
STATUS="$(jqget "$SCOPE" '.status // "unknown"' unknown)"
TARGET="$(jqget "$SCOPE" '.target // "unknown"' unknown)"
START_TIME="$(jqget "$SCOPE" '.start_time // ""' '')"

ELAPSED="$(python3 - "$START_TIME" <<'PY' 2>/dev/null || printf 'unknown'
import sys
from datetime import datetime, timezone
raw = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
if not raw:
    print("unknown"); raise SystemExit
try:
    start = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
except ValueError:
    print("unknown"); raise SystemExit
secs = int((datetime.now(timezone.utc) - start).total_seconds())
print(f"{secs // 3600}h{(secs % 3600) // 60:02d}m{secs % 60:02d}s")
PY
)"

OPSEC_MODE="$(jqget "$SCOPE" '.opsec_mode // "normal"' normal)"

echo "SNAPSHOT_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "ENG_DIR=$ENG_DIR"
echo "SCOPE target=$TARGET status=$STATUS phase=$PHASE elapsed=$ELAPSED"
echo "OPSEC=$OPSEC_MODE"
if [[ "$OPSEC_MODE" != "normal" && "$OPSEC_MODE" != "agressif" ]]; then
    echo "OPSEC_NOTE: standing constraint — passif = zero packets to target; stealth = GET-first, <=1 req/s, stop on 429/WAF. Cases not workable in this mode get REQUEUEd with reason opsec_mode."
fi

# --- queue (one sqlite call per aggregate, not one per question) -------------
if [[ -f "$CASES_DB" ]]; then
    echo "QUEUE total=$(sql 'SELECT COUNT(*) FROM cases;') processing=$(sql "SELECT COUNT(*) FROM cases WHERE status='processing';") pending=$(sql "SELECT COUNT(*) FROM cases WHERE status='pending';")"
    printf 'BY_STAGE %s\n' "$(sql "SELECT group_concat(stage || '=' || c, ' ') FROM (SELECT stage, COUNT(*) AS c FROM cases GROUP BY stage ORDER BY stage);")"
    printf 'IN_FLIGHT %s\n' "$(sql "SELECT COALESCE(group_concat(tag || '=' || c, ' '), 'none') FROM (SELECT COALESCE(assigned_agent, 'unassigned') AS tag, COUNT(*) AS c FROM cases WHERE status='processing' GROUP BY assigned_agent);")"
else
    echo "QUEUE cases.db missing"
fi

# --- respawn flags (auth + osint) -------------------------------------------
if [[ -x "$SCRIPT_DIR/auth_respawn_check.sh" ]]; then
    "$SCRIPT_DIR/auth_respawn_check.sh" "$ENG_DIR" >/dev/null 2>&1 || true
fi
if [[ -x "$SCRIPT_DIR/intel_changed_check.sh" ]]; then
    "$SCRIPT_DIR/intel_changed_check.sh" "$ENG_DIR" >/dev/null 2>&1 || true
fi
AUTH_FLAG=0
OSINT_FLAG=0
[[ -f "$ENG_DIR/.auth-respawn-required" ]] && AUTH_FLAG=1
[[ -f "$ENG_DIR/.osint-respawn-required" ]] && OSINT_FLAG=1
echo "FLAGS auth_respawn=$AUTH_FLAG osint_respawn=$OSINT_FLAG"

# --- findings + campaign graph ----------------------------------------------
# `grep -c` prints 0 and exits 1 on no-match, so swallow the status but keep the count.
FINDING_COUNT=0
if [[ -f "$FINDINGS" ]]; then
    FINDING_COUNT="$(grep -c '^## \[FINDING' "$FINDINGS" 2>/dev/null || true)"
    [[ "$FINDING_COUNT" =~ ^[0-9]+$ ]] || FINDING_COUNT=0
fi
echo "FINDINGS count=$FINDING_COUNT"
echo "GRAPH intents=$(jqget "$GRAPH" '(.intents // []) | length' 0) facts=$(jqget "$GRAPH" '(.facts // []) | length' 0)"

# --- stop lock ---------------------------------------------------------------
if engagement_is_locked "$ENG_DIR"; then
    echo "STOP_LOCK=held reason=$(engagement_lock_reason "$ENG_DIR")"
    echo "STOP_LOCK_NOTE: dispatch is frozen; no fetch will be served until the lock is cleared."
else
    echo "STOP_LOCK=none"
fi

# --- polling budget (last, so the warning is the final line the operator reads)
note_state_read "$ENG_DIR" "$PHASE"
