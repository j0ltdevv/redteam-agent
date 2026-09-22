#!/usr/bin/env bash
# intel.sh -- separation public intel.md versus vault intel-secrets.json
# Equivalent local documente sans dotenvx ni vault externe et sans install globale
# Le vault local repose sur trois mecanismes simples
# Fichier intel-secrets.json avec permissions 600 forcees a chaque acces
# Secret transmis via stdin ou fichier jamais en argument ni en echo clair
# Logs et previews avec placeholder [REDACTED] uniquement
# Correctif permissions runtime constate sur .interactsh.env en 644
# intel_fix_runtime_secret_perms corrige a 600 tout fichier secret existant
# Le fichier .interactsh.env reste gitignore et nest jamais ecrit dans git

intel_secret_file() {
    local eng_dir="${1:?engagement dir required}"
    printf "%s\n" "$eng_dir/intel-secrets.json"
}

intel_looks_like_secret() {
    local candidate="${1:-}"
    if [[ -z "$candidate" ]]
    then
        return 1
    fi
    printf "%s" "$candidate" | grep -Eq "AKIA|ghp_|sk-|Bearer|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]"
}

intel_guard_public_value() {
    local candidate="${1:-}"
    if intel_looks_like_secret "$candidate"
    then
        printf "%s\n" "[intel] refused secret pattern in public intel.md value ([REDACTED])" >&2 || true
        return 1
    fi
}

intel_scan_public_file() {
    local public_file="${1:?public file required}"
    if [[ ! -f "$public_file" ]]
    then
        return 0
    fi
    if grep -Eq "AKIA|ghp_|sk-|Bearer|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]" "$public_file"
    then
        printf "%s\n" "[intel] secret pattern found in public file ([REDACTED])" >&2 || true
        return 1
    fi
}

intel_append_public_row() {
    local eng_dir="${1:?engagement dir required}"
    local row_type="${2:?type required}"
    local raw_value="${3:-}"
    local row_ref="${4:-}"
    local row_source="${5:-}"
    local row_notes="${6:-}"
    if intel_looks_like_secret "$raw_value"
    then
        printf "%s\n" "[intel] refused raw secret for intel.md use store_intel_secret.sh ([REDACTED])" >&2 || true
        return 1
    fi
    if intel_looks_like_secret "$row_notes"
    then
        printf "%s\n" "[intel] refused secret pattern in public notes ([REDACTED])" >&2 || true
        return 1
    fi
    local intel_md="$eng_dir/intel.md"
    printf "| %s | %s | %s | %s | %s |\n" "$row_type" "[REDACTED]" "$row_ref" "$row_source" "$row_notes" >> "$intel_md" || return 1
}

intel_harden_secret_perms() {
    local f=""
    for f in "$@"
    do
        if [[ -f "$f" ]]
        then
            chmod 600 "$f" || return 1
        fi
    done
}

intel_fix_runtime_secret_perms() {
    local eng_dir="${1:?engagement dir required}"
    local secret_path="$eng_dir/intel-secrets.json"
    if [[ -f "$secret_path" ]]
    then
        chmod 600 "$secret_path" || return 1
    fi
    local local_env="$eng_dir/.interactsh.env"
    if [[ -f "$local_env" ]]
    then
        chmod 600 "$local_env" || return 1
    fi
    local repo_root=""
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)" || true
    if [[ -n "$repo_root" ]]
    then
        if [[ -f "$repo_root/.opencode/.interactsh.env" ]]
        then
            chmod 600 "$repo_root/.opencode/.interactsh.env" || return 1
        fi
    fi
}

ensure_intel_secret_store() {
    local eng_dir="${1:?engagement dir required}"
    local path=""
    path="$(intel_secret_file "$eng_dir")" || return 1
    if [[ ! -s "$path" ]]
    then
        (
        umask 077 || exit 1
        printf "[]\n" > "$path" || exit 1
        ) || return 1
    fi
    chmod 600 "$path" || return 1
    intel_fix_runtime_secret_perms "$eng_dir" || true
}

truncate_secret_preview() {
    printf "%s\n" "[REDACTED]" || true
}

_intel_commit_secret() {
    local path="${1:?store path required}"
    local staging="${2:?secret staging file required}"
    local ref="${3:?ref required}"
    local typ="${4:?type required}"
    local source="${5:-}"
    local notes="${6:-}"
    local tmp=""
    tmp="$(mktemp "${TMPDIR:-/tmp/opencode}/intel-secrets.XXXXXX")" || return 1
    chmod 600 "$tmp" || return 1
    if python3 - <<"PY" "$path" "$tmp" "$staging" "$ref" "$typ" "$source" "$notes"
import json
import sys
path = sys.argv[1]
tmp = sys.argv[2]
staging = sys.argv[3]
ref = sys.argv[4]
typ = sys.argv[5]
source = sys.argv[6]
notes = sys.argv[7]
with open(staging, "r", encoding="utf-8") as fh:
    val = fh.read()
with open(path, "r", encoding="utf-8") as fh:
    rows = json.load(fh)
updated = False
for row in rows:
    if row.get("ref") == ref:
        row.update({"type": typ, "value": val, "source": source, "notes": notes})
        updated = True
        break
if not updated:
    rows.append({"ref": ref, "type": typ, "value": val, "source": source, "notes": notes})
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(rows, fh, indent=2)
    fh.write("\n")
PY
    then
        mv "$tmp" "$path" || return 1
        chmod 600 "$path" || return 1
        rm -f "$staging" || true
        rm -f "$tmp" || true
    else
        rm -f "$tmp" || true
        rm -f "$staging" || true
        return 1
    fi
}

upsert_intel_secret() {
    local eng_dir="${1:?engagement dir required}"
    local ref="${2:?ref required}"
    local type="${3:?type required}"
    local value="${4:-}"
    local source="${5:-}"
    local notes="${6:-}"
    local path=""
    local staging=""
    printf "%s\n" "[intel] direct argument deprecated use --stdin or --value-file ([REDACTED])" >&2 || true
    ensure_intel_secret_store "$eng_dir" || return 1
    path="$(intel_secret_file "$eng_dir")" || return 1
    mkdir -p "${TMPDIR:-/tmp/opencode}" || return 1
    staging="$(mktemp "${TMPDIR:-/tmp/opencode}/intel-value.XXXXXX")" || return 1
    chmod 600 "$staging" || return 1
    printf "%s" "$value" > "$staging" || return 1
    _intel_commit_secret "$path" "$staging" "$ref" "$type" "$source" "$notes" || return 1
    intel_fix_runtime_secret_perms "$eng_dir" || true
}

upsert_intel_secret_stdin() {
    local eng_dir="${1:?engagement dir required}"
    local ref="${2:?ref required}"
    local type="${3:?type required}"
    local source="${4:-}"
    local notes="${5:-}"
    local path=""
    local staging=""
    ensure_intel_secret_store "$eng_dir" || return 1
    path="$(intel_secret_file "$eng_dir")" || return 1
    mkdir -p "${TMPDIR:-/tmp/opencode}" || return 1
    staging="$(mktemp "${TMPDIR:-/tmp/opencode}/intel-value.XXXXXX")" || return 1
    chmod 600 "$staging" || return 1
    cat > "$staging" || return 1
    _intel_commit_secret "$path" "$staging" "$ref" "$type" "$source" "$notes" || return 1
    intel_fix_runtime_secret_perms "$eng_dir" || true
}

upsert_intel_secret_file() {
    local eng_dir="${1:?engagement dir required}"
    local ref="${2:?ref required}"
    local type="${3:?type required}"
    local secret_src="${4:?secret file required}"
    local source="${5:-}"
    local notes="${6:-}"
    local path=""
    local staging=""
    if [[ ! -f "$secret_src" ]]
    then
        printf "%s\n" "[intel] secret file not found ([REDACTED])" >&2 || true
        return 1
    fi
    ensure_intel_secret_store "$eng_dir" || return 1
    path="$(intel_secret_file "$eng_dir")" || return 1
    mkdir -p "${TMPDIR:-/tmp/opencode}" || return 1
    staging="$(mktemp "${TMPDIR:-/tmp/opencode}/intel-value.XXXXXX")" || return 1
    chmod 600 "$staging" || return 1
    cat "$secret_src" > "$staging" || return 1
    _intel_commit_secret "$path" "$staging" "$ref" "$type" "$source" "$notes" || return 1
    intel_fix_runtime_secret_perms "$eng_dir" || true
}
