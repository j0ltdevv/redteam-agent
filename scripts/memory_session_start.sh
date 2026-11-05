#!/usr/bin/env bash
# ============================================================================
#  memory_session_start.sh — charge le brief mémoire long au démarrage d'une
#  session redteam (MCP Basic Memory, projet « memory »).
#
#  Usage: bash ./scripts/memory_session_start.sh [question-de-recherche]
#
#  Best-effort : si le service basic-memory-mcp n'est pas joignable, on
#  n'échoue PAS (un pentest ne doit pas dépendre de la disponibilité d'un
#  vault). Le statut est indiqué, l'agent continue avec la mémoire locale
#  (playbooks générés) comme source de vérité.
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MEMORY_URL="${BASIC_MEMORY_URL:-http://127.0.0.1:27842/mcp}"
QUERY="${1:-redteam pentest egress OPSECBubble WireGuard Tor engagement}"
TIMEOUT="${MEMORY_TIMEOUT:-3}"

if ! curl -s -m "$TIMEOUT" -o /dev/null "$MEMORY_URL" 2>/dev/null; then
    # Un GET nu sur /mcp renvoie 400/405 quand le serveur MCP est vivant : on
    # teste la connectivité TCP plutot que le code HTTP.
    if ! (exec 3<>"/dev/tcp/${MEMORY_URL#http://}" ) 2>/dev/null; then
        echo "memory=absent basic-memory injoignable sur $MEMORY_URL — repli sur les playbooks locaux"
        exit 0
    fi
fi

echo "memory=ok basic-memory joignable sur $MEMORY_URL"

# Recherche via le MCP si la CLI basic-memory est disponible.
if command -v basic-memory >/dev/null 2>&1; then
    echo "--- brief mémoire (recherche: $QUERY) ---"
    basic-memory tool search-notes "$QUERY" 2>/dev/null | head -40 || true
else
    echo "CLI basic-memory absente : interroger le MCP basic-memory directement (outil search_notes)."
    echo "Requête suggérée : $QUERY"
fi

# Les playbooks générés restent prioritaires : ils sont locaux et par cible.
GEN="$REPO_ROOT/.opencode/playbooks/generated"
if [ -d "$GEN" ] && [ -n "$(ls -A "$GEN" 2>/dev/null)" ]; then
    echo "--- playbooks générés disponibles ---"
    ls -1t "$GEN"/*.md 2>/dev/null | head -5 | sed 's|^|  |'
fi
