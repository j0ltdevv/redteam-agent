#!/usr/bin/env bash
set -euo pipefail
# store_intel_secret.sh -- ecrit un secret dans intel-secrets.json jamais dans intel.md
# Equivalent local documente sans dotenvx ni vault externe et sans install globale
# Secret via stdin ou fichier jamais en echo clair et jamais en log clair
# Preview et logs avec placeholder [REDACTED] uniquement
# Permissions 600 forcees sur intel-secrets.json et .interactsh.env existant
# Le fichier .interactsh.env reste gitignore et nest jamais ecrit dans git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/intel.sh" || exit 1

usage() {
    printf "%s\n" "usage: store_intel_secret.sh <engagement_dir> <ref> <type> (--stdin | --value-file <path> | <value-deprecated>) <source> [notes]" >&2 || true
    exit 1
}

ENG_DIR="${1:-}"
REF="${2:-}"
TYPE="${3:-}"
MODE="${4:-}"

[ -n "$ENG_DIR" ] || usage
[ -n "$REF" ] || usage
[ -n "$TYPE" ] || usage
[ -n "$MODE" ] || usage

VALUE_MODE="direct"
VALUE=""
VALUE_FILE=""
SOURCE_NAME=""
NOTES=""

if [[ "$MODE" == "--stdin" ]]
then
    VALUE_MODE="stdin"
    SOURCE_NAME="${5:-}"
    NOTES="${6:-}"
elif [[ "$MODE" == "--value-file" ]]
then
    VALUE_MODE="file"
    VALUE_FILE="${5:-}"
    SOURCE_NAME="${6:-}"
    NOTES="${7:-}"
    [ -n "$VALUE_FILE" ] || usage
else
    printf "%s\n" "[store-intel-secret] direct argument refused, use --stdin or --value-file ([REDACTED])" >&2 || true
    exit 2
fi

if intel_looks_like_secret "$NOTES" || intel_looks_like_secret "$SOURCE_NAME"
then
    printf "%s\n" "[store-intel-secret] refused secret pattern in source or notes ([REDACTED])" >&2 || true
    exit 1
fi

if [[ "$VALUE_MODE" == "stdin" ]]
then
    upsert_intel_secret_stdin "$ENG_DIR" "$REF" "$TYPE" "$SOURCE_NAME" "$NOTES" || exit 1
elif [[ "$VALUE_MODE" == "file" ]]
then
    upsert_intel_secret_file "$ENG_DIR" "$REF" "$TYPE" "$VALUE_FILE" "$SOURCE_NAME" "$NOTES" || exit 1
else
    upsert_intel_secret "$ENG_DIR" "$REF" "$TYPE" "$VALUE" "$SOURCE_NAME" "$NOTES" || exit 1
fi

intel_fix_runtime_secret_perms "$ENG_DIR" || true

PREVIEW="$(truncate_secret_preview)" || exit 1
printf "| %s | %s | %s | %s | %s |\n" "$TYPE" "$PREVIEW" "$REF" "$SOURCE_NAME" "$NOTES" || exit 1
printf "%s\n" "[store-intel-secret] stored $REF ([REDACTED])" >&2 || true
