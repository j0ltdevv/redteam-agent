#!/usr/bin/env bash
# generate_playbook.sh — capitalise un engagement terminé en playbook réutilisable.
#
# Usage: bash scripts/generate_playbook.sh <engagement_dir>
# Produit: .opencode/playbooks/generated/<hostname>-<date>.md (style SKILL.md,
# frontmatter YAML compatible agentskills.io / Hermes-style discovery).
#
# Le playbook capture: profil cible, techniques qui ont validé (findings),
# pièges rencontrés (log), et commandes exactes réutilisables.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENG_DIR="${1:?usage: generate_playbook.sh <engagement_dir>}"
[[ -d "$ENG_DIR" ]] || { echo "engagement dir not found: $ENG_DIR" >&2; exit 1; }
ENG_DIR="$(cd "$ENG_DIR" && pwd)"

SCOPE_FILE="$ENG_DIR/scope.json"
FINDINGS_FILE="$ENG_DIR/findings.md"
LOG_FILE="$ENG_DIR/log.md"

[[ -f "$SCOPE_FILE" ]] || { echo "scope.json not found in $ENG_DIR" >&2; exit 1; }
[[ -f "$FINDINGS_FILE" ]] || { echo "findings.md not found in $ENG_DIR" >&2; exit 1; }

OUT_DIR="$REPO_ROOT/.opencode/playbooks/generated"
mkdir -p "$OUT_DIR"

# --- Extraction -----------------------------------------------------------

target="$(jq -r '.target // "unknown"' "$SCOPE_FILE")"
hostname_raw="$(jq -r '.hostname // "unknown"' "$SCOPE_FILE")"
start_time="$(jq -r '.start_time // "unknown"' "$SCOPE_FILE")"
status="$(jq -r '.status // "unknown"' "$SCOPE_FILE")"
eng_date="${start_time:0:10}"

slug="$(echo "$hostname_raw" | tr '.' '-' | tr -cd 'a-zA-Z0-9-')"
out_file="$OUT_DIR/${slug}-${eng_date}.md"

finding_count="$(grep -c '^## \[FINDING-' "$FINDINGS_FILE" 2>/dev/null || echo 0)"

# Résumé des findings: titre + sévérité + type, une ligne de tableau par finding.
# Utilise awk en mode paragraphe: chaque bloc FINDING produit une ligne |titre|sévérité|type|.
findings_digest="$(awk '
  BEGIN { title = ""; severity = "-"; ftype = "-" }
  /^## \[FINDING-/ {
      if (title != "") printf "| %s | %s | %s |\n", title, severity, ftype
      title = $0; sub(/^## /, "", title)
      gsub(/\|/, "\\|", title)
      severity = "-"; ftype = "-"
      next
  }
  /^- \*\*Severity\*\*:/ {
      severity = $0; sub(/^- \*\*Severity\*\*: */, "", severity)
      next
  }
  /^- \*\*Type\*\*:/ {
      ftype = $0; sub(/^- \*\*Type\*\*: */, "", ftype)
      gsub(/\|/, "\\|", ftype)
      next
  }
  END { if (title != "") printf "| %s | %s | %s |\n", title, severity, ftype }
' "$FINDINGS_FILE")"

# Pièges: entrées de log mentionnant erreur/fallback/broken/refusé, dédupliquées.
pitfalls="$(grep -iE 'broken|fallback|failed|refus|error|unresolved|killed|timed out|rate.?limit|blocked' "$LOG_FILE" 2>/dev/null \
  | grep -vE '^[[:space:]]*$' | awk '!seen[$0]++' | head -8 || true)"

# Commandes notables: lignes avec run_tool/curl/nmap/ffuf/sqlmap/nuclei dans le log.
commands_used="$(grep -oE '(run_tool|nmap|ffuf|sqlmap|nuclei|whatweb|katana|curl)[^|]*' "$LOG_FILE" 2>/dev/null | sort -u | head -12 || true)"

# Phases complétées
phases="$(jq -r '.phases_completed // [] | join(", ")' "$SCOPE_FILE" 2>/dev/null || echo "")"

# --- Rendu ----------------------------------------------------------------

cat > "$out_file" << EOF
---
name: ${slug}-${eng_date}
description: Playbook auto-généré depuis l'engagement ${eng_date} contre ${hostname_raw} (${finding_count} findings). Charge ce playbook au démarrage d'un engagement sur une cible similaire (SPA web, API REST, même stack).
generated_from: ${ENG_DIR#$REPO_ROOT/}
target: ${target}
engagement_date: ${eng_date}
engagement_status: ${status}
finding_count: ${finding_count}
phases_completed: ${phases:-none}
triggers:
  - webapp
  - spa
  - api-rest
  - juice-shop
---

# Playbook — ${hostname_raw} (${eng_date})

## Profil cible

- **Target**: ${target}
- **Findings validés**: ${finding_count}
- **Phases complétées**: ${phases:-aucune (engagement non finalisé)}

## Techniques qui ont validé (à rejouer en priorité)

| Finding | Sévérité | Type |
|---|---|---|
${findings_digest}

## Pièges rencontrés (ne pas refaire)

$( [[ -n "$pitfalls" ]] && echo "$pitfalls" | sed 's/^/- /' || echo "- (aucun piège majeur consigné)")

## Commandes qui ont servi

$( [[ -n "$commands_used" ]] && echo "$commands_used" | sed 's/^/- /' || echo "- (voir log.md pour le détail)")

## Sources

- Findings: \`${ENG_DIR#$REPO_ROOT/}/findings.md\`
- Log: \`${ENG_DIR#$REPO_ROOT/}/log.md\`
- Scope: \`${ENG_DIR#$REPO_ROOT/}/scope.json\`

---

*Généré automatiquement par \`scripts/generate_playbook.sh\` — édite librement pour raffiner les procédures.*
EOF

echo "Playbook écrit: ${out_file#$REPO_ROOT/}"
echo "Findings: ${finding_count} | Target: ${hostname_raw} | Status: ${status}"
