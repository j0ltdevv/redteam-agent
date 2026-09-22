#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/engagement.sh"
EMIT_RUNTIME_EVENT="$SCRIPT_DIR/emit_runtime_event.sh"

usage() {
    cat >&2 <<'USAGE'
usage: graph.sh [engagement_dir] <add <fact|intent|hint> <text> [source] | list [fact|intent|hint] | resolve <intent_id> [note]>
USAGE
    exit 2
}

kind_to_array() {
    case "$1" in
        fact)   printf 'facts' ;;
        intent) printf 'intents' ;;
        hint)   printf 'hints' ;;
        *)      return 1 ;;
    esac
}

kind_to_prefix() {
    case "$1" in
        fact)   printf 'F-' ;;
        intent) printf 'I-' ;;
        hint)   printf 'H-' ;;
        *)      return 1 ;;
    esac
}

# normalize_graph_text <text>: ascii_downcase + squeeze whitespace + trim
normalize_graph_text() {
    jq -rn --arg t "$1" '$t | ascii_downcase | gsub("[[:space:]]+"; " ") | ltrimstr(" ") | rtrimstr(" ")'
}

now_utc() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

ensure_graph() {
    if [[ -f "$GRAPH_FILE" ]]; then
        return 0
    fi
    mkdir -p "$ENG_DIR"
    local now
    now="$(now_utc)"
    cat > "$GRAPH_FILE" << EOF
{
  "updated": "${now}",
  "facts": [],
  "intents": [],
  "hints": []
}
EOF
}

# emit_graph_event <summary> <payload-json> — best-effort, silent unless the
# helper exists and ORCHESTRATOR_* is configured; never fails the graph op.
emit_graph_event() {
    local summary="$1"
    local payload_json="$2"
    [[ -f "$EMIT_RUNTIME_EVENT" ]] || return 0
    [[ -n "${ORCHESTRATOR_BASE_URL:-}" \
       && -n "${ORCHESTRATOR_TOKEN:-}" \
       && -n "${ORCHESTRATOR_PROJECT_ID:-}" \
       && -n "${ORCHESTRATOR_RUN_ID:-}" ]] || return 0
    bash "$EMIT_RUNTIME_EVENT" \
        "graph.updated" \
        "${ORCHESTRATOR_PHASE:-unknown}" \
        "${ORCHESTRATOR_TASK:-graph}" \
        "${ORCHESTRATOR_AGENT:-operator}" \
        "$summary" \
        --payload-json "$payload_json" || true
    return 0
}

[[ $# -ge 1 ]] || usage

# Optional leading <engagement_dir>; otherwise ENGAGEMENT_DIR env / engagements/.active
ENG_DIR_ARG=""
if [[ "$1" != "add" && "$1" != "list" && "$1" != "resolve" ]]; then
    ENG_DIR_ARG="$1"
    shift
fi

[[ $# -ge 1 ]] || usage
CMD="$1"
shift

if [[ -n "$ENG_DIR_ARG" ]]; then
    ENG_DIR="$(canonicalize_engagement_dir "$(pwd)" "$ENG_DIR_ARG" 2>/dev/null || true)"
    if [[ -z "$ENG_DIR" ]]; then
        printf 'ERROR: engagement dir not found: %s\n' "$ENG_DIR_ARG" >&2
        exit 1
    fi
else
    ENG_DIR="$(resolve_engagement_dir "$(pwd)" 2>/dev/null || true)"
    if [[ -z "$ENG_DIR" ]]; then
        printf 'ERROR: could not resolve engagement dir (set ENGAGEMENT_DIR or engagements/.active)\n' >&2
        exit 1
    fi
fi

GRAPH_FILE="$ENG_DIR/graph.json"

case "$CMD" in
    add)
        [[ $# -ge 2 ]] || usage
        KIND="$1"
        TEXT="$2"
        SOURCE="${3:-}"
        ARRAY="$(kind_to_array "$KIND")" || usage
        PREFIX="$(kind_to_prefix "$KIND")" || usage
        ensure_graph

        NORMALIZED="$(normalize_graph_text "$TEXT")"
        DUP_ID="$(jq -r --arg arr "$ARRAY" --arg norm "$NORMALIZED" '
            [ (.[$arr] // [])[]
              | select(((.text // "") | ascii_downcase | gsub("[[:space:]]+"; " ") | ltrimstr(" ") | rtrimstr(" ")) == $norm)
              | .id ][0] // ""
        ' "$GRAPH_FILE")"
        if [[ -n "$DUP_ID" ]]; then
            printf 'DUPLICATE %s\n' "$DUP_ID"
            exit 0
        fi

        NEXT_NUM="$(jq -r --arg arr "$ARRAY" '
            [ (.[$arr] // [])[] | (.id // "") | sub("^[A-Za-z]+-"; "") | tonumber? ] | (max // 0) + 1
        ' "$GRAPH_FILE")"
        NEW_ID="$(printf '%s%03d' "$PREFIX" "$NEXT_NUM")"
        NOW="$(now_utc)"

        jq --arg arr "$ARRAY" \
           --arg id "$NEW_ID" \
           --arg text "$TEXT" \
           --arg source "$SOURCE" \
           --arg created "$NOW" \
           '.[$arr] += [{id: $id, text: $text, source: $source, created: $created}]
            | .updated = $created' \
           "$GRAPH_FILE" > "$GRAPH_FILE.tmp" && mv "$GRAPH_FILE.tmp" "$GRAPH_FILE"

        printf 'ADDED %s\n' "$NEW_ID"

        PAYLOAD="$(jq -cn --arg id "$NEW_ID" --arg kind "$KIND" --arg text "$TEXT" \
            '{id: $id, kind: $kind, text: $text}')"
        emit_graph_event "graph ${KIND} added: ${NEW_ID}: ${TEXT}" "$PAYLOAD"
        exit 0
        ;;

    list)
        KIND_FILTER="${1:-}"
        ensure_graph
        if [[ -n "$KIND_FILTER" ]]; then
            ARRAY="$(kind_to_array "$KIND_FILTER")" || usage
            jq -c --arg arr "$ARRAY" '(.[$arr] // []) | sort_by(.id)' "$GRAPH_FILE"
        else
            jq -c '[ (.facts // [])[], (.intents // [])[], (.hints // [])[] ] | sort_by(.id)' "$GRAPH_FILE"
        fi
        exit 0
        ;;

    resolve)
        [[ $# -ge 1 ]] || usage
        INTENT_ID="$1"
        NOTE="${2:-}"
        ensure_graph

        if ! jq -e --arg id "$INTENT_ID" 'any((.intents // [])[]; .id == $id)' "$GRAPH_FILE" >/dev/null; then
            if jq -e --arg id "$INTENT_ID" 'any(((.facts // []) + (.hints // []))[]; .id == $id)' "$GRAPH_FILE" >/dev/null; then
                printf 'ERROR: %s is not an intent\n' "$INTENT_ID" >&2
            else
                printf 'ERROR: intent %s not found\n' "$INTENT_ID" >&2
            fi
            exit 1
        fi

        NOW="$(now_utc)"
        jq --arg id "$INTENT_ID" \
           --arg note "$NOTE" \
           --arg ts "$NOW" \
           '.intents |= map(if .id == $id then (.resolved = true | .resolved_at = $ts | .resolved_note = $note) else . end)
            | .updated = $ts' \
           "$GRAPH_FILE" > "$GRAPH_FILE.tmp" && mv "$GRAPH_FILE.tmp" "$GRAPH_FILE"

        printf 'RESOLVED %s\n' "$INTENT_ID"

        PAYLOAD="$(jq -cn --arg id "$INTENT_ID" --arg note "$NOTE" '{id: $id, note: $note}')"
        emit_graph_event "graph intent resolved: ${INTENT_ID}" "$PAYLOAD"
        exit 0
        ;;

    *)
        usage
        ;;
esac
