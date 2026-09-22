#!/usr/bin/env bash
# validate_finding.sh <finding.json> — gate déterministe 6 étapes (T05 copilot v2).
# exit 0 = validated, exit 1 = unconfirmed/rejected. Aucun jugement LLM : exécution réelle.
set -u

F="${1:-}"
[ -z "$F" ] && { echo "usage: validate_finding.sh <finding.json>"; exit 1; }
[ -f "$F" ] || { echo "KO stage=inventory: fichier introuvable $F"; exit 1; }

jq_strip() { jq -r "$1" "$F" 2>/dev/null; }

# --- 1. inventory : ID + target + type obligatoires ---
ID=$(jq_strip '.id')
TARGET=$(jq_strip '.target')
TYPE=$(jq_strip '.type')
if [ -z "$ID" ] || [ "$ID" = "null" ] || [ -z "$TARGET" ] || [ "$TARGET" = "null" ] \
   || [ -z "$TYPE" ] || [ "$TYPE" = "null" ]; then
  echo "KO stage=inventory: id/target/type manquants"; exit 1
fi

# --- 2. analysis : hypothèse + falsificateur obligatoires ---
HYP=$(jq_strip '.hypothesis')
FALS=$(jq_strip '.falsifier')
if [ -z "$HYP" ] || [ "$HYP" = "null" ] || [ -z "$FALS" ] || [ "$FALS" = "null" ]; then
  echo "KO stage=analysis: hypothesis/falsifier manquants"; exit 1
fi

# --- 3. sanity_check : PREUVE EXÉCUTÉE réelle (commande + sortie) ---
CMD=$(jq_strip '.evidence.command')
OUT=$(jq_strip '.evidence.output')
if [ -z "$CMD" ] || [ "$CMD" = "null" ] || [ -z "$OUT" ] || [ "$OUT" = "null" ]; then
  echo "KO stage=sanity_check: evidence.command/output absents (aucune exécution = pas de finding)"; exit 1
fi
# la sortie doit être non vide et contenir un motif observable déclaré
EXPECT=$(jq_strip '.evidence.expect_regex')
if [ -n "$EXPECT" ] && [ "$EXPECT" != "null" ]; then
  if ! printf '%s' "$OUT" | grep -qE "$EXPECT"; then
    echo "KO stage=sanity_check: la preuve ne matche pas expect_regex ($EXPECT)"; exit 1
  fi
fi
# hash de la preuve (reproductibilité)
PROOF_HASH=$(printf '%s' "$OUT" | sha256sum | cut -c1-16)

# --- 4. ruling : 2 sources indépendantes -> confirmed, 1 -> unconfirmed, 0 -> rejected ---
SOURCES=$(jq_strip '.sources')
N=$(printf '%s' "$SOURCES" | tr ',' '\n' | sed '/^$/d' | sort -u | wc -l)
if [ "$N" -ge 2 ]; then
  RULING="confirmed"
elif [ "$N" -eq 1 ]; then
  RULING="unconfirmed"
else
  echo "KO stage=ruling: aucune source outil"; exit 1
fi
if [ "$RULING" != "confirmed" ]; then
  echo "KO stage=ruling: $N source(s) — 2 minimum requises (unconfirmed)"; exit 1
fi

# --- 5. feasibility : reproductible en 1 commande strictement égale ---
REPRO=$(jq_strip '.reproduce_command')
if [ -z "$REPRO" ] || [ "$REPRO" = "null" ]; then
  echo "KO stage=feasibility: reproduce_command manquant"; exit 1
fi
if [ "$REPRO" != "$CMD" ]; then
  echo "KO stage=feasibility: reproduce_command != evidence.command"; exit 1
fi

# --- 6. validated ---
CONF=$(jq_strip '.confidence')
echo "OK stage=validated id=$ID target=$TARGET type=$TYPE sources=$SOURCES proof_hash=$PROOF_HASH confidence=${CONF:-?}"
exit 0
