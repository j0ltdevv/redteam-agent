#!/usr/bin/env bash
set -euo pipefail

# stop_engagement.sh — the ONLY supported way to stop an engagement.
#
# A stop must be atomic. Concretely, in this order:
#   1. take the stop lock  → from this instant the dispatcher refuses every fetch
#   2. release in-flight cases back to `pending` so a later /resume can recover them
#   3. stop the engagement's containers
#   4. write the stop reason into log.md
#   5. compose a partial report so the run never ends empty-handed
#
# Step 1 comes first on purpose: if the lock went down last, a subagent result
# landing in between could still pull a fresh batch. That is exactly how the
# 2026-09-23-235052-172-20-0-2 run kept working for 20 minutes after the stop.
#
# Usage:
#   stop_engagement.sh <engagement_dir> [--reason CODE] [--detail TEXT]
#                                      [--no-containers] [--no-report] [--quiet]
#   stop_engagement.sh <engagement_dir> --clear     # lift the lock (resume)
#   stop_engagement.sh <engagement_dir> --status    # show lock + queue, no writes
#
# Reason codes (same vocabulary as operator-core.md):
#   completed | queue_incomplete | surface_coverage_incomplete |
#   collection_unhealthy | runtime_error | manual_stop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/engagement.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/engagement_lock.sh"

usage() {
    cat >&2 <<'EOF'
Usage:
  stop_engagement.sh <engagement_dir> [--reason CODE] [--detail TEXT]
                                     [--no-containers] [--no-report] [--quiet]
  stop_engagement.sh <engagement_dir> --clear     # lift the lock (resume)
  stop_engagement.sh <engagement_dir> --status    # show lock + queue, no writes

Reason codes (same vocabulary as operator-core.md):
  completed | queue_incomplete | surface_coverage_incomplete |
  collection_unhealthy | runtime_error | manual_stop
EOF
    exit 1
}

ENG_DIR_ARG=""
REASON="manual_stop"
DETAIL=""
DO_CONTAINERS=1
DO_REPORT=1
QUIET=0
MODE="stop"

while (($# > 0)); do
    case "$1" in
        --reason)     REASON="${2:?--reason requires a value}"; shift 2 ;;
        --detail)     DETAIL="${2:?--detail requires a value}"; shift 2 ;;
        --no-containers) DO_CONTAINERS=0; shift ;;
        --no-report)  DO_REPORT=0; shift ;;
        --quiet)      QUIET=1; shift ;;
        --clear)      MODE="clear"; shift ;;
        --status)     MODE="status"; shift ;;
        -h|--help)    usage ;;
        -*)           echo "unknown flag: $1" >&2; usage ;;
        *)            ENG_DIR_ARG="$1"; shift ;;
    esac
done

case "$REASON" in
    completed|queue_incomplete|surface_coverage_incomplete|collection_unhealthy|runtime_error|manual_stop)
        ;;
    *)
        echo "ERROR: invalid --reason '$REASON'" >&2
        echo "       allowed: completed|queue_incomplete|surface_coverage_incomplete|collection_unhealthy|runtime_error|manual_stop" >&2
        exit 1
        ;;
esac

if [[ -n "$ENG_DIR_ARG" ]]; then
    ENG_DIR="$(canonicalize_engagement_dir "$(pwd)" "$ENG_DIR_ARG" 2>/dev/null || true)"
    [[ -n "$ENG_DIR" ]] || { echo "engagement directory not found: $ENG_DIR_ARG" >&2; exit 1; }
else
    ENG_DIR="$(resolve_engagement_dir "$(pwd)" || true)"
fi
[[ -n "$ENG_DIR" ]] || { echo "no engagement directory could be resolved (pass one explicitly)" >&2; exit 1; }

CASES_DB="$ENG_DIR/cases.db"

db_count() {
    # db_count <sql> → number, or empty when cases.db is missing/broken
    [[ -f "$CASES_DB" ]] || return 0
    sqlite3 "$CASES_DB" ".timeout 5000" "$1" 2>/dev/null || true
}

print_status() {
    local processing pending active reason
    processing="$(db_count "SELECT COUNT(*) FROM cases WHERE status='processing';")"
    pending="$(db_count "SELECT COUNT(*) FROM cases WHERE status='pending';")"
    active="$(db_count "SELECT COUNT(*) FROM cases WHERE stage IN ('ingested','vuln_confirmed','fuzz_pending');")"
    reason="$(engagement_lock_reason "$ENG_DIR")"

    printf 'ENG_DIR=%s\n' "$ENG_DIR"
    if engagement_is_locked "$ENG_DIR"; then
        printf 'STOP_LOCK=held reason=%s\n' "${reason:-unknown}"
    else
        printf 'STOP_LOCK=none\n'
    fi
    printf 'QUEUE active=%s processing=%s pending=%s\n' \
        "${active:-0}" "${processing:-0}" "${pending:-0}"
}

if [[ "$MODE" == "status" ]]; then
    print_status
    exit 0
fi

if [[ "$MODE" == "clear" ]]; then
    release_stop_lock "$ENG_DIR"
    if [[ -x "$SCRIPT_DIR/append_log_entry.sh" ]]; then
        "$SCRIPT_DIR/append_log_entry.sh" "$ENG_DIR" operator "Stop lock cleared" \
            "manual_resume" "operator lifted the stop lock; queue dispatch is available again" \
            >/dev/null 2>&1 || true
    fi
    print_status
    exit 0
fi

# ---------------------------------------------------------------- 1. the lock
acquire_stop_lock "$ENG_DIR" "$REASON" "${DETAIL:-operator stop}"

# --------------------------------------------------- 2. release in-flight work
RELEASED=0
if [[ -f "$CASES_DB" ]]; then
    RELEASED="$(db_count "SELECT COUNT(*) FROM cases WHERE status='processing';")"
    RELEASED="${RELEASED:-0}"
    sqlite3 "$CASES_DB" ".timeout 5000" \
        "UPDATE cases SET status='pending', assigned_agent=NULL, consumed_at=NULL WHERE status='processing';" \
        >/dev/null 2>&1 || true
fi

# --------------------------------------------------------- 3. stop containers
if ((DO_CONTAINERS)) && [[ -f "$SCRIPT_DIR/lib/container.sh" ]]; then
    # shellcheck source=/dev/null
    ( source "$SCRIPT_DIR/lib/container.sh"
      export ENGAGEMENT_DIR="$ENG_DIR"
      stop_all_containers ) 2>/dev/null || true
fi

# -------------------------------------------------------------- 4. stop reason
if [[ -x "$SCRIPT_DIR/append_log_entry.sh" ]]; then
    "$SCRIPT_DIR/append_log_entry.sh" "$ENG_DIR" operator "Run stop" \
        "stop_reason=$REASON" \
        "${DETAIL:-operator stop}; released ${RELEASED} in-flight case(s) back to pending; queue locked against new dispatch" \
        >/dev/null 2>&1 || true
fi

# --------------------------------------------------------- 5. partial report
# Never swallow the outcome silently: an empty/failed partial report is how a
# run ends with findings.md full and report.md absent (observed 2026-09-23:
# the 0-byte report.md.partial marker with no visible failure).
REPORT_STATUS="skipped"
if ((DO_REPORT)); then
    if [[ -x "$SCRIPT_DIR/compose_partial_report.sh" ]]; then
        if REPORT_OUT="$("$SCRIPT_DIR/compose_partial_report.sh" "$ENG_DIR" 2>&1)"; then
            if [[ -s "$ENG_DIR/report.md" ]]; then
                REPORT_STATUS="ok"
            else
                REPORT_STATUS="empty"
                echo "WARN: compose_partial_report.sh exited 0 but report.md is empty" >&2
            fi
        else
            REPORT_STATUS="failed"
            printf 'WARN: compose_partial_report.sh failed: %s\n' "$REPORT_OUT" >&2
        fi
    else
        REPORT_STATUS="missing-script"
        echo "WARN: compose_partial_report.sh not found; report.md not composed" >&2
    fi
fi

if ((QUIET == 0)); then
    echo
    echo "=== Engagement stopped ==="
    print_status
    printf 'RELEASED_IN_FLIGHT=%s\n' "$RELEASED"
    printf 'PARTIAL_REPORT=%s\n' "$REPORT_STATUS"
    echo
    echo "The dispatcher now refuses every fetch for this engagement."
    echo "Resume with: ./scripts/stop_engagement.sh \"$ENG_DIR\" --clear"
    echo "Stop reason: $REASON — ${DETAIL:-operator stop}"
fi
