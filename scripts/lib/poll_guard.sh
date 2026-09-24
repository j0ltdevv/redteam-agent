#!/usr/bin/env bash
# poll_guard.sh — per-phase state-read budget.
#
# Why this exists: on engagements/2026-09-23-235052-172-20-0-2 the operator ran
# `dispatcher.sh ... stats-by-stage` 29 times, `grep -c '^## \[FINDING'` 9 times,
# `intel_changed_check.sh` 8 times, and the two respawn flag files 9 times —
# roughly 60 shell round-trips spent re-confirming state it already had, each one
# re-sending a ~300k-token context. Re-reading state is not progress, and it was
# the single largest source of lost wall-clock time in that run.
#
# The counter below turns that habit into a visible, countable signal instead of
# a silent cost.

STATE_SNAPSHOT_STATE_NAME=".state-snapshot.json"
REDTEAM_STATUS_MAX_PER_PHASE="${REDTEAM_STATUS_MAX_PER_PHASE:-3}"

# state_snapshot_path <engagement_dir>
state_snapshot_path() {
    local dir="${1:?engagement_dir required}"
    printf '%s/%s\n' "${dir%/}" "$STATE_SNAPSHOT_STATE_NAME"
}

# note_state_read <engagement_dir> <phase>
# Increments the read counter for <phase> and prints SNAPSHOT_CALLS=<n>, plus a
# POLL_WARNING line once the per-phase budget is exceeded. The counter resets
# whenever the derived phase changes, so a budget is per phase, not per run.
note_state_read() {
    local dir="${1:?engagement_dir required}"
    local phase="${2:-unknown}"
    local path count stored_phase tmp

    path="$(state_snapshot_path "$dir")"
    count=0
    stored_phase=""

    if [[ -f "$path" ]] && command -v jq >/dev/null 2>&1; then
        stored_phase="$(jq -r '.phase // ""' "$path" 2>/dev/null || printf '')"
        count="$(jq -r '.count // 0' "$path" 2>/dev/null || printf '0')"
    fi
    [[ "$count" =~ ^[0-9]+$ ]] || count=0

    if [[ -n "$stored_phase" && "$stored_phase" == "$phase" ]]; then
        count=$(( count + 1 ))
    else
        stored_phase="$phase"
        count=1
    fi

    if command -v jq >/dev/null 2>&1; then
        tmp="$path.tmp"
        if jq -cn --arg phase "$stored_phase" --argjson count "$count" \
               --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
               '{phase:$phase, count:$count, at:$at}' > "$tmp" 2>/dev/null; then
            mv "$tmp" "$path"
        else
            rm -f "$tmp"
        fi
    fi

    printf 'SNAPSHOT_CALLS=%s\n' "$count"
    if (( count > REDTEAM_STATUS_MAX_PER_PHASE )); then
        printf 'POLL_WARNING: %s snapshot(s) taken in phase %s (budget %s).\n' \
            "$count" "$stored_phase" "$REDTEAM_STATUS_MAX_PER_PHASE"
        printf 'POLL_WARNING: stop snapshotting and make an advancing call instead —\n'
        printf 'POLL_WARNING: re-reading state is not progress (see operator-core.md, State Reads).\n'
    fi
}

# reset_state_reads <engagement_dir>
reset_state_reads() {
    local dir="${1:?engagement_dir required}"
    rm -f "$(state_snapshot_path "$dir")"
}
