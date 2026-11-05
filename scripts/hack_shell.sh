#!/usr/bin/env bash
# =============================================================================
#  hack_shell.sh — shell interne du terminal REDTEAM.
#
#  Affiche le splash (scripts/hack_banner.sh) puis lance le TUI OpenCode dans
#  le projet redteam-agent. Ce script existe pour que le lanceur rt-hack n'ait
#  qu'une seule chose à passer à kitty : un exécutable + ses arguments.
#
#  Le splash ne bloque pas l'agent : il mesure, il affiche, puis cède la main.
#  Si une mesure échoue, la ligne le dit (fail-closed visuel).
#
#  Usage (via rt-hack, normalement) :
#    hack_shell.sh          → splash + TUI
#    hack_shell.sh -c       → splash + reprise de session
#    RT_SKIP_BANNER=1       → TUI seul (travail en cours, pas de splash)
# =============================================================================
set -uo pipefail

RT_DIR="${RT_DIR:-$HOME/redteam-agent}"
BANNER="$RT_DIR/scripts/hack_banner.sh"

[ -d "$RT_DIR" ] || { printf 'hack_shell: projet introuvable: %s\n' "$RT_DIR" >&2; exit 1; }

# La palette du TUI vient de ~/.config/opencode/cli.json (theme redteam) et le
# terminal de ~/.config/kitty/redteam.conf : rien n'est defini ici.
export COLORTERM=truecolor

cd "$RT_DIR" || exit 1

if [ "${RT_SKIP_BANNER:-0}" != "1" ] && [ -x "$BANNER" ]; then
  bash "$BANNER" || printf '\n  [splash indisponible — voir %s]\n' "$BANNER"
fi

# RT_HACK_TUI_SHELL=1 : teste le splash tout seul, sans lancer l'agent.
if [ "${RT_HACK_TUI_SHELL:-0}" = "1" ]; then
  exit 0
fi

# 2026-09-25 (comme rt-term) : --standalone OBLIGATOIRE. opencode v2 n'a qu'un
# seul enregistrement de service (~/.local/state/opencode/service.json) : sans
# ce flag, ce terminal rejoint la melee et tue le service des autres front-ends
# (Desktop, autres terminaux, bot Telegram) → saisie clavier perdue, Entree sans
# effet, redemarrages en boucle. --standalone = serveur prive, zero collision.
exec opencode --standalone "$@"
