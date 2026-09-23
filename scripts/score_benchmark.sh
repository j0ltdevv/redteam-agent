#!/usr/bin/env bash
# score_benchmark.sh <engagement_dir> [ground-truth.json] — précision/rappel style EthiBench.
# TP = finding dont le titre matche un challenge ground-truth (match normalisé, sous-chaîne).
# Précision = TP / findings totaux. Rappel = challenges touchés / challenges totaux.
# Ne touche ni à la doctrine ni aux findings : lecture seule + rapport stdout.
set -uo pipefail

ENG_DIR="${1:?usage: score_benchmark.sh <engagement_dir> [ground-truth.json]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GT="${2:-$SCRIPT_DIR/../benchmark/ground-truth.json}"
FINDINGS="$ENG_DIR/findings.md"

[ -f "$FINDINGS" ] || { echo "findings.md introuvable dans $ENG_DIR" >&2; exit 1; }
[ -f "$GT" ] || { echo "ground-truth introuvable: $GT" >&2; exit 1; }

norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }

mapfile -t TITLES < <(grep -oE '^\#\# \[(FINDING-[A-Z]{2}-[0-9]{3})\][[:space:]]+.*$' "$FINDINGS" \
    | sed -E 's/^\#\# \[FINDING-[A-Z]{2}-[0-9]{3}\][[:space:]]+//' || true)
mapfile -t CHALLENGES < <(jq -r '.challenges[]' "$GT")

TOTAL_FINDINGS="${#TITLES[@]}"
TOTAL_GT="${#CHALLENGES[@]}"
[ "$TOTAL_FINDINGS" -gt 0 ] || { echo "score: aucun finding — precision=0 recall=0 (0/0 findings, 0/$TOTAL_GT challenges)"; exit 0; }

TP=0
declare -A HIT=()
FALSE_POSITIVES=()
for t in "${TITLES[@]}"; do
    nt="$(norm "$t")"
    matched=""
    for c in "${!CHALLENGES[@]}"; do
        nc="$(norm "${CHALLENGES[$c]}")"
        if [[ "$nt" == *"$nc"* ]] || [[ "$nc" == *"$nt"* ]]; then
            matched="${CHALLENGES[$c]}"
            HIT["$c"]=1
            break
        fi
    done
    if [ -n "$matched" ]; then
        TP=$((TP + 1))
    else
        FALSE_POSITIVES+=("$t")
    fi
done
HIT_COUNT="${#HIT[@]}"

read -r PRECISION RECALL F1 <<<"$(awk -v tp="$TP" -v f="$TOTAL_FINDINGS" -v h="$HIT_COUNT" -v g="$TOTAL_GT" 'BEGIN {
    p = (f > 0) ? tp / f : 0; r = (g > 0) ? h / g : 0;
    f1 = (p + r > 0) ? 2 * p * r / (p + r) : 0;
    printf "%.3f %.3f %.3f", p, r, f1
}')"

echo "score: precision=$PRECISION recall=$RECALL f1=$F1 (tp=$TP/$TOTAL_FINDINGS findings, $HIT_COUNT/$TOTAL_GT challenges)"
if [ "${#FALSE_POSITIVES[@]}" -gt 0 ]; then
    echo "false-positives (${#FALSE_POSITIVES[@]}):"
    printf '  - %s\n' "${FALSE_POSITIVES[@]}"
fi
MISSED=()
for c in "${!CHALLENGES[@]}"; do
    [ -n "${HIT[$c]:-}" ] || MISSED+=("${CHALLENGES[$c]}")
done
if [ "${#MISSED[@]}" -gt 0 ]; then
    echo "missed (${#MISSED[@]}):"
    printf '  - %s\n' "${MISSED[@]}"
fi
