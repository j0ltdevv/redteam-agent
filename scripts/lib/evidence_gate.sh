#!/usr/bin/env bash
# evidence_gate.sh — the exploited stage is not free.
#
# Why this exists: on engagements/2026-09-23-235052-172-20-0-2 the operator
# marked cases 13,14,15 as `exploited` with no exploit work performed —
# "marking exploited to unblock queue" after exploit-developer policy-blocked
# twice. A stage transition that can be advanced without an artifact is a
# stage transition that will be advanced falsely.
#
# require_exploit_evidence <evidence_path> <db_path>
#   exits 1 when:
#     - no --evidence path was given
#     - the path does not exist or is empty
#     - the path resolves outside the engagement directory owning <db_path>
#
# Expects engagement_dir_from_db() from lib/engagement_lock.sh to be sourced.

require_exploit_evidence() {
    local path="${1:-}"
    local db="${2:?db path required}"
    local dir resolved

    dir="$(engagement_dir_from_db "$db")"

    if [[ -z "$path" ]]; then
        cat >&2 <<EOF
FATAL: refusing to mark exploited without evidence.
       Add --evidence <path> pointing at the artefact that proves the exploit
       (e.g. \$DIR/scans/<case>-<slug>.md, \$DIR/downloads/<slug>.body, or
       \$DIR/scans/finding-<slug>.json).
       'exploited to unblock the queue' transitions are contract violations:
       an unproven exploited case corrupts the report and the recall gate.
EOF
        exit 1
    fi

    if [[ ! -f "$path" || ! -s "$path" ]]; then
        echo "FATAL: evidence file missing or empty: $path" >&2
        exit 1
    fi

    resolved="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    case "$resolved" in
        "$dir"/*) ;;
        *)
            echo "FATAL: evidence must live inside the engagement dir ($dir): $resolved" >&2
            exit 1
            ;;
    esac
}
