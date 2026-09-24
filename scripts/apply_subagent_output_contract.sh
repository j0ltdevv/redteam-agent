#!/usr/bin/env bash
set -euo pipefail

# apply_subagent_output_contract.sh — inject the shared output-budget contract
# into every subagent prompt file under .opencode/prompts/agents/.
#
# The contract lives in ONE place (scripts/lib/subagent_output_contract.md) and
# is copied into each prompt as a marked, managed block. Re-running this script
# replaces the block in place, so the prompt files never accumulate duplicates.
#
# .opencode/prompts/agents/operator.txt is deliberately skipped: it is rendered
# from operator-core.md by scripts/render-operator-prompts.sh, and its copy of
# the contract is maintained there.
#
# Usage: apply_subagent_output_contract.sh [--check]
#   --check → exit 1 if any prompt file is missing or has a stale contract block

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_DIR="$REPO_ROOT/.opencode/prompts/agents"
CONTRACT="$SCRIPT_DIR/lib/subagent_output_contract.md"

BEGIN_MARK="<!-- BEGIN subagent-output-contract (managed by scripts/apply_subagent_output_contract.sh) -->"
END_MARK="<!-- END subagent-output-contract -->"

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

[[ -f "$CONTRACT" ]] || { echo "contract source missing: $CONTRACT" >&2; exit 1; }
[[ -d "$PROMPT_DIR" ]] || { echo "prompt dir missing: $PROMPT_DIR" >&2; exit 1; }

declare -a MISSING=()

for prompt in "$PROMPT_DIR"/*.txt; do
    name="$(basename "$prompt")"
    [[ "$name" == "operator.txt" ]] && continue

    if grep -Fq "$BEGIN_MARK" "$prompt"; then
        if (( CHECK_ONLY )); then
            # Verify the managed block still matches the canonical contract.
            if ! awk -v b="$BEGIN_MARK" -v e="$END_MARK" \
                'index($0,b){f=1;next} index($0,e){f=0} f' "$prompt" \
                | diff -q - <(cat "$CONTRACT") >/dev/null 2>&1; then
                MISSING+=("$name (stale block)")
            fi
        fi
        continue
    fi

    if (( CHECK_ONLY )); then
        MISSING+=("$name (no contract block)")
        continue
    fi

    {
        printf '\n%s\n' "$BEGIN_MARK"
        cat "$CONTRACT"
        printf '%s\n' "$END_MARK"
    } >> "$prompt"
    printf 'updated %s\n' "$name"
done

if ((${#MISSING[@]} > 0)); then
    echo "subagent output contract FAILED for:" >&2
    printf '  - %s\n' "${MISSING[@]}" >&2
    echo "Run: scripts/apply_subagent_output_contract.sh" >&2
    exit 1
fi

if (( CHECK_ONLY )); then
    echo "subagent output contract OK"
else
    echo "subagent output contract applied"
fi
