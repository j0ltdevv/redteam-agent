#!/usr/bin/env bash
# engagement_lock.sh — atomic stop-lock primitives for a single engagement.
#
# Why this exists: `stop` used to be a log line. The operator could write
# `stop_reason=manual_stop` and keep dispatching, because nothing on the queue
# path knew the run was over. Observed on engagements/2026-09-23-235052-172-20-0-2:
# the stop was recorded, in-flight subagents were never cancelled, their results
# landed 20 minutes later, and three new findings were appended after the stop.
# A stop that is not enforced at the dispatcher is not a stop.
#
# The lock file is the enforcement point: every queue-mutating dispatch entry
# point refuses to hand out work while <engagement_dir>/.stop-lock exists.
#
# Exit code 3 is reserved for "refused because the engagement is stopped".

ENGAGEMENT_LOCK_NAME=".stop-lock"

# engagement_lock_path <engagement_dir>
engagement_lock_path() {
    local dir="${1:?engagement_dir required}"
    printf '%s/%s\n' "${dir%/}" "$ENGAGEMENT_LOCK_NAME"
}

# engagement_dir_from_db <db_path> — resolve the owning engagement dir of a
# cases.db so dispatcher.sh can locate its lock without extra plumbing.
engagement_dir_from_db() {
    local db="${1:?db path required}"
    local dir
    dir="$(dirname "$db")"
    (cd "$dir" >/dev/null 2>&1 && pwd) || printf '%s\n' "$dir"
}

# engagement_is_locked <engagement_dir>
engagement_is_locked() {
    local dir="${1:?engagement_dir required}"
    [[ -f "$(engagement_lock_path "$dir")" ]]
}

# engagement_lock_reason <engagement_dir> — prints the recorded reason code,
# or nothing when the lock is absent.
engagement_lock_reason() {
    local dir="${1:?engagement_dir required}"
    local path
    path="$(engagement_lock_path "$dir")"
    [[ -f "$path" ]] || return 0
    if command -v jq >/dev/null 2>&1; then
        jq -r '.reason // "unknown"' "$path" 2>/dev/null || printf 'unknown\n'
    else
        sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$path" | head -1
    fi
}

# acquire_stop_lock <engagement_dir> <reason_code> [detail]
# Idempotent: a second call while the lock is held is a no-op that reports the
# existing lock instead of overwriting the original stop reason.
acquire_stop_lock() {
    local dir="${1:?engagement_dir required}"
    local reason="${2:-manual_stop}"
    local detail="${3:-}"
    local path at
    path="$(engagement_lock_path "$dir")"
    at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [[ -f "$path" ]]; then
        printf 'stop lock already held (reason=%s): %s\n' \
            "$(engagement_lock_reason "$dir")" "$path"
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg reason "$reason" --arg detail "$detail" --arg at "$at" \
            --argjson pid "$$" \
            '{reason:$reason, detail:$detail, at:$at, pid:$pid}' > "$path.tmp"
        mv "$path.tmp" "$path"
    else
        printf '{"reason":"%s","detail":"%s","at":"%s","pid":%s}\n' \
            "$reason" "$detail" "$at" "$$" > "$path"
    fi

    printf 'stop lock acquired (reason=%s): %s\n' "$reason" "$path"
}

# release_stop_lock <engagement_dir> — lift the lock. Only an explicit operator
# resume may do this; it does NOT restart any queue loop by itself.
release_stop_lock() {
    local dir="${1:?engagement_dir required}"
    local path
    path="$(engagement_lock_path "$dir")"
    if [[ -f "$path" ]]; then
        rm -f "$path"
        printf 'stop lock released: %s\n' "$path"
    else
        printf 'no stop lock present: %s\n' "$path"
    fi
}

# require_unlocked <engagement_dir> <action_name>
# Hard gate for queue-mutating actions. Exits 3 when the engagement is stopped.
require_unlocked() {
    local dir="${1:?engagement_dir required}"
    local action="${2:-dispatch}"
    local path reason
    path="$(engagement_lock_path "$dir")"
    [[ -f "$path" ]] || return 0

    reason="$(engagement_lock_reason "$dir")"
    cat >&2 <<EOF
FATAL: engagement is STOPPED — refusing ${action}.
       stop lock  : $path
       stop reason: ${reason}
       No new work may be dispatched while the lock is held. To resume the run
       an operator must explicitly lift it first:
         ./scripts/stop_engagement.sh "$dir" --clear
EOF
    exit 3
}
