#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/findings.sh"
EMIT_RUNTIME_EVENT="$SCRIPT_DIR/emit_runtime_event.sh"

ENG_DIR="${1:?usage: append_finding.sh <engagement_dir> <agent-name> <finding-body-file>}"
AGENT_NAME="${2:?usage: append_finding.sh <engagement_dir> <agent-name> <finding-body-file>}"
BODY_FILE="${3:?usage: append_finding.sh <engagement_dir> <agent-name> <finding-body-file>}"
FINDINGS_FILE="$ENG_DIR/findings.md"

VALIDATE_FINDING="$SCRIPT_DIR/validate_finding.sh"

[[ -f "$FINDINGS_FILE" ]] || { echo "findings.md not found in $ENG_DIR" >&2; exit 1; }
[[ -f "$BODY_FILE" ]] || { echo "finding body file not found: $BODY_FILE" >&2; exit 1; }

# --- Garde de preuve (fail-closed) ---------------------------------------
# Principe : "No exploit, no finding." Aucun finding n'entre dans findings.md
# sans passer le gate déterministe validate_finding.sh (6 étapes, exécution
# réelle : evidence.command/output/expect_regex, 2 sources indépendantes,
# reproduce_command strictement égal à la commande de preuve).
#
# Ce gate était jusqu'ici documenté dans 20 endroits mais jamais appelé par
# le seul script qui écrit dans findings.md : la règle n'était pas mécanique.
# Ici elle l'est. Un finding sans preuve est refusé, pas signalé.
#
# La preuve est lue depuis le frontmatter JSON du fichier body (bloc
# ```evidence … ```) ou, à défaut, depuis un .json sibling du body.
# --------------------------------------------------------------------------

extract_evidence_json() {
    local body="$1" candidate

    # 1) Bloc ```evidence fenced dans le body
    if awk '/^```evidence[[:space:]]*$/{f=1;next} /^```[[:space:]]*$/{if(f){exit}} f' "$body" \
        | jq -e . >/dev/null 2>&1; then
        awk '/^```evidence[[:space:]]*$/{f=1;next} /^```[[:space:]]*$/{if(f){exit}} f' "$body"
        return 0
    fi

    # 2) JSON sibling : scans/finding-xxx.md -> scans/finding-xxx.json
    candidate="${body%.*}.json"
    if [ -f "$candidate" ] && jq -e . "$candidate" >/dev/null 2>&1; then
        cat "$candidate"
        return 0
    fi

    return 1
}

if [ ! -x "$VALIDATE_FINDING" ] && [ ! -f "$VALIDATE_FINDING" ]; then
    echo "KO gate=missing: validate_finding.sh introuvable — refus d'écrire un finding sans gate" >&2
    exit 1
fi

if ! evidence_json="$(extract_evidence_json "$BODY_FILE")"; then
    echo "KO stage=sanity_check: aucune preuve dans $BODY_FILE" >&2
    echo "  Attendu : bloc \`\`\`evidence … \`\`\` (JSON) dans le body, ou ${BODY_FILE%.*}.json" >&2
    echo "  Rappel   : un finding sans commande exécutée + sortie observée n'est pas un finding." >&2
    exit 1
fi

evidence_file="$(mktemp "${TMPDIR:-/tmp}/finding-evidence.XXXXXX")"
trap 'rm -f "${evidence_file:-}"' EXIT
printf '%s' "$evidence_json" >"$evidence_file"

validation_out=""
if ! validation_out="$(bash "$VALIDATE_FINDING" "$evidence_file" 2>&1)"; then
    echo "KO gate=rejected: finding refusé par validate_finding.sh" >&2
    printf '%s\n' "$validation_out" | sed 's/^/  /' >&2
    exit 1
fi

printf '%s\n' "$validation_out" | sed 's/^/  [gate] /' >&2

# Hash de preuve conservé pour traçabilité dans findings.md.
# On ne mute JAMAIS le fichier body fourni par l'appelant : le hash est
# ajouté au tmp_file, après résolution du placeholder d'ID.
proof_hash="$(printf '%s' "$validation_out" | grep -oE 'proof_hash=[0-9a-f]+' | cut -d= -f2 || true)"

lock_dir="$(acquire_finding_lock "$ENG_DIR")"
tmp_file=""
trap 'rm -f "${evidence_file:-}" "${tmp_file:-}"; [[ -n "${lock_dir:-}" ]] && release_finding_lock "$lock_dir"' EXIT

finding_id="$(next_finding_id "$ENG_DIR" "$AGENT_NAME")"
tmp_file="$(mktemp "${TMPDIR:-/tmp}/finding-append.XXXXXX")"

if ! replace_finding_placeholder "$BODY_FILE" "$finding_id" "$tmp_file"; then
    rm -f "$tmp_file"
    echo "finding body must contain a heading with [FINDING-ID] placeholder or existing finding id" >&2
    exit 1
fi

if [ -n "$proof_hash" ]; then
    printf '\n<!-- gate:validate_finding.sh proof_hash=%s -->\n' "$proof_hash" >>"$tmp_file"
fi

candidate_title="$(extract_finding_title "$tmp_file")"
existing_id="$(find_existing_finding_id "$FINDINGS_FILE" "$tmp_file")"
if [[ -n "$existing_id" ]]; then
    rm -f "$tmp_file"
    if [[ -n "$candidate_title" ]]; then
        printf 'duplicate finding already present as %s: %s\n' "$existing_id" "$candidate_title" >&2
    else
        printf 'duplicate finding already present as %s\n' "$existing_id" >&2
    fi
    printf '%s\n' "$existing_id"
    exit 0
fi

{
    printf '\n'
    cat "$tmp_file"
    printf '\n'
} >>"$FINDINGS_FILE"

update_finding_count "$FINDINGS_FILE"

rm -f "$tmp_file"
if [[ -f "$EMIT_RUNTIME_EVENT" ]]; then
    # Best-effort extraction: severity/category are optional.
    # Parse from body lines like "**Severity**: critical" / "**Category**: injection".
    severity="$(grep -oE '^\*\*Severity\*\*:[[:space:]]*[A-Za-z]+' "$BODY_FILE" 2>/dev/null \
                | sed 's/^.*:[[:space:]]*//' | tr 'A-Z' 'a-z' || true)"
    category="$(grep -oE '^\*\*Category\*\*:[[:space:]]*[A-Za-z0-9-]+' "$BODY_FILE" 2>/dev/null \
                | sed 's/^.*:[[:space:]]*//' | tr 'A-Z' 'a-z' || true)"
    payload="$(jq -cn \
        --arg finding_id "$finding_id" \
        --arg severity "${severity:-}" \
        --arg category "${category:-}" \
        --arg title "${candidate_title:-}" \
        '{finding_id:$finding_id, severity:$severity, category:$category, title:$title}')"
    bash "$EMIT_RUNTIME_EVENT" \
        "finding.created" \
        "${ORCHESTRATOR_PHASE:-unknown}" \
        "$finding_id" \
        "$AGENT_NAME" \
        "${candidate_title:-Added $finding_id}" \
        --kind finding \
        --payload-json "$payload"
fi
printf '%s\n' "$finding_id"
