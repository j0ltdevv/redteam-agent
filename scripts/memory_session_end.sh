#!/usr/bin/env bash
# ============================================================================
#  memory_session_end.sh — capitalise un engagement dans la mémoire longue
#  (inter-engagements), par extraction méthodologique, PAS par recopie.
#
#  Usage: bash ./scripts/memory_session_end.sh <engagement_dir>
#
#  Règle OPSEC : ce qui part en mémoire longue, c'est la MÉTHODE, jamais la
#  cible. Toutes les identités de cible (IP, hostname, domaine, token, cookie,
#  chemin sensible) sont filtrées AVANT écriture. Le vault est partagé avec la
#  session normale : y écrire « 10.0.3.7 vulnérable » casserait la
#  compartimentation. On écrit « contournement de filtre par octet nul validé
#  sur service FTP ancien ».
#
#  Best-effort : un vault indisponible ne doit pas faire échouer la fin
#  d'engagement. Le playbook local (generate_playbook.sh) reste la vérité.
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENG_DIR="${1:?usage: memory_session_end.sh <engagement_dir>}"
[[ -d "$ENG_DIR" ]] || { echo "engagement dir introuvable: $ENG_DIR" >&2; exit 1; }
ENG_DIR="$(cd "$ENG_DIR" && pwd)"

FINDINGS_FILE="$ENG_DIR/findings.md"
LOG_FILE="$ENG_DIR/log.md"
SCOPE_FILE="$ENG_DIR/scope.json"

# --- 1. Redaction des identités de cible ----------------------------------
# Liste des valeurs à neutraliser, tirées du scope de l'engagement.
declare -a SECRETS=()
if [ -f "$SCOPE_FILE" ]; then
    while IFS= read -r val; do
        [ -n "$val" ] && SECRETS+=("$val")
    done < <(jq -r '.. | strings' "$SCOPE_FILE" 2>/dev/null \
        | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b|\b[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9-]+)+\b' \
        | grep -vE '^(http|https|ftp)$' | sort -u)
fi
# Les identifiants d'engagement ne sont pas des secrets, mais on masque le slug.
SECRETS+=("$(basename "$ENG_DIR")")

redact() {
    local text="$1" s
    for s in "${SECRETS[@]}"; do
        [ -z "$s" ] && continue
        text="$(printf '%s' "$text" | sed -E "s|${s//./\\.}|[cible]|g")"
    done
    # Tokens / cookies résiduels.
    text="$(printf '%s' "$text" | sed -E 's/(token|cookie|api[_-]?key|secret|password)=[^ &"]+/\1=[redacted]/gi')"
    printf '%s' "$text"
}

# --- 2. Extraction des leçons méthodologiques ------------------------------
lessons=""
if [ -f "$FINDINGS_FILE" ]; then
    lessons="$(awk '
      BEGIN { title=""; sev=""; ftype=""; inblock=0 }
      /^## \[FINDING-/ {
          if (title != "") print "| " title " | " (sev==""?"-":sev) " | " (ftype==""?"-":ftype) " |"
          title=""; sev=""; ftype=""; inblock=1
          line=$0
          sub(/^## \[FINDING-[A-Z]+-[0-9]+\] /,"",line)
          title=line
          next
      }
      inblock && /\*\*Severity\*\*/ { gsub(/.*Severity\*\*: *| *$/,""); sev=tolower($0); next }
      inblock && /\*\*Category\*\*/ { gsub(/.*Category\*\*: *| *$/,""); ftype=tolower($0); next }
      END { if (title != "") print "| " title " | " (sev==""?"-":sev) " | " (ftype==""?"-":ftype) " |" }
    ' "$FINDINGS_FILE")"
fi

n_findings=0
[ -n "$lessons" ] && n_findings="$(printf '%s\n' "$lessons" | grep -c . || echo 0)"

# --- 3. Écriture ----------------------------------------------------------
if [ "$n_findings" -eq 0 ]; then
    echo "memory=skip aucun finding dans findings.md — rien à capitaliser"
    exit 0
fi

body="$(cat <<EOF
---
title: Leçons redteam $(date +%Y-%m-%d)
type: note
tags: [redteam, pentest, methodology, lecons]
updated: $(date +%Y-%m-%d)
---

# Leçons redteam — $(date +%Y-%m-%d)

Capitalisation méthodologique d'un engagement terminé. Les identités de cible
sont volontairement absentes : seule la méthode est transposable.

## Techniques qui ont validé

| Technique | Sévérité | Type |
|---|---|---|
$(redact "$lessons")
EOF
)"

if command -v basic-memory >/dev/null 2>&1; then
    err_file="$(mktemp "${TMPDIR:-/tmp}/bm-write.XXXXXX")"
    if printf '%s' "$body" | basic-memory tool write-note \
            --title "Leçons redteam $(date +%Y-%m-%d)" \
            --folder "redteam/leçons" \
            --tags "redteam,pentest,methodology,lecons" \
            --type note 2>"$err_file"; then
        echo "memory=written note écrite dans memory/redteam/leçons"
    else
        echo "memory=error écriture vault échouée (non bloquant) :"
        sed 's/^/  /' "$err_file" | head -8
    fi
    rm -f "$err_file"
else
    echo "memory=local CLI basic-memory absente — note NON écrite, voici le contenu :"
    printf '%s\n' "$body"
fi

# --- 4. Playbook local (toujours, indépendamment du vault) ----------------
if [ -x "$SCRIPT_DIR/generate_playbook.sh" ] || [ -f "$SCRIPT_DIR/generate_playbook.sh" ]; then
    bash "$SCRIPT_DIR/generate_playbook.sh" "$ENG_DIR" >/dev/null 2>&1 \
        && echo "playbook=régénéré .opencode/playbooks/generated/" \
        || echo "playbook=error génération échouée"
fi
