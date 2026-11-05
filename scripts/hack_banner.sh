#!/usr/bin/env bash
# =============================================================================
#  hack_banner.sh — splash du terminal REDTEAM (lancé par ~/.local/bin/rt-hack)
#
#  RÈGLE DOCTRINALE : ce bannier n'affiche AUCUNE valeur inventée. Chaque ligne
#  est soit MESURÉE (relevée à l'instant), soit DÉCLARÉE (lue dans la config du
#  projet). La distinction est écrite dans le libellé, jamais cachée. Un agent
#  dont l'écran ment sur son propre état est un agent qu'on ne peut pas auditer.
#
#  Mesuré : hôte, heure, egress (opsec-check.sh), engagement (operator_status.sh),
#           conteneurs lab (docker).
#  Déclaré : modèle, agent par défaut, nombre de MCP (opencode.jsonc, lu en JSONC).
#
#  Si une mesure ne répond pas dans le budget, la ligne affiche « non mesurable »
#  — jamais une valeur par défaut, jamais un silence qui ressemble à un OK.
# =============================================================================
set -uo pipefail

RT_DIR="${RT_DIR:-$HOME/redteam-agent}"
CFG="$RT_DIR/.opencode/opencode.jsonc"
EGRESS_TIMEOUT="${RT_BANNER_EGRESS_TIMEOUT:-10}"

R=$'\033[1;31m'    # rouge vif
D=$'\033[2;31m'    # rouge sombre
P=$'\033[38;5;203m' # rouge pâle
A=$'\033[38;5;215m' # ambre
G=$'\033[38;5;114m' # vert
W=$'\033[38;5;252m' # blanc cassé
M=$'\033[38;5;244m' # gris
Z=$'\033[0m'

banner() {
  printf '%s\n' "$R"
  cat << 'EOF'
  ██████╗ ███████╗███████╗████████╗███████╗ █████╗ ███╗   ███╗
  ██╔══██╗██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
  ██████╔╝█████╗  █████╗     ██║   █████╗  ███████║██╔████╔██║
  ██╔══██╗██╔══╝  ██╔══╝     ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║
  ██║  ██║███████╗███████╗   ██║   ███████╗██║  ██║██║ ╚═╝ ██║
  ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
EOF
  printf '%s\n' "$Z"
}

kv() { printf '  %s%-13s%s %s\n' "$M" "$1" "$Z" "$2"; }

# --- egress : MESURÉ via l'autorité unique (opsec-check.sh), budget 8s --------
egress_line() {
  local out verdict ip
  if ! out=$(timeout "$EGRESS_TIMEOUT" "$RT_DIR/scripts/opsec-check.sh" 2>/dev/null); then
    printf '%snon mesurable en %ss → voir ./scripts/opsec-check.sh%s' "$A" "$EGRESS_TIMEOUT" "$Z"
    return
  fi
  verdict=$(printf '%s' "$out" | grep -o 'VERDICT *: *[A-Z_]*' | head -1 | sed 's/.*: *//')
  ip=$(printf '%s' "$out" | grep 'IP de sortie' | head -1 | sed 's/.*: *//' | tr -d ' ')
  case "${verdict:-}" in
    BULLE|WG|VPN|TUNNEL) printf '%s%s%s via %s' "$G" "${verdict:-TUNNEL}" "$Z" "${ip:-?}" ;;
    CLAIR)              printf '%sCLAIR — trafic EN CLAIR%s via %s' "$R" "$Z" "${ip:-?}" ;;
    *)                  printf '%sINCONNU — fail-closed, aucun engagement autorisé%s' "$A" "$Z" ;;
  esac
}

# --- engagement : MESURÉ ----------------------------------------------------
engagement_line() {
  local st
  st=$(timeout 20 "$RT_DIR/scripts/operator_status.sh" 2>/dev/null)
  if [ -z "$st" ]; then
    printf '%saucun engagement lisible%s' "$M" "$Z"
    return
  fi
  local scope findings queue
  # La ligne SCOPE porte deja target/status/phase/elapsed : on la rend telle
  # quelle plutot que de la reparcourir (les doublons affiches faussent la
  # lecture et rappellent mal qui a mesure quoi).
  scope=$(printf '%s' "$st"   | grep -m1 '^SCOPE '     | sed 's/^SCOPE //')
  findings=$(printf '%s' "$st" | grep -m1 '^FINDINGS ' | sed 's/^FINDINGS count=//')
  queue=$(printf '%s' "$st"   | grep -m1 '^QUEUE '    | sed 's/^QUEUE //')
  printf '%s' "${scope:-inconnu}"
  [ -n "$queue" ]    && printf '  %squeue: %s%s'     "$D" "$queue" "$Z"
  [ -n "$findings" ] && printf '  %sfindings: %s%s' "$P" "$findings" "$Z"
  return 0
}

# --- lab : MESURÉ ------------------------------------------------------------
lab_line() {
  local up down
  up=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -cE '^(lab-kali|mock-api|portal-spa|fake-aruba|fake-sentry|hotel-lab)')
  down=$(docker ps -a --format '{{.Names}} {{.State}}' 2>/dev/null | grep -E '^(lab-kali|mock-api|portal-spa|fake-aruba|fake-sentry|hotel-lab)' | grep -c 'exited')
  if [ "${up:-0}" -gt 0 ]; then
    printf '%s%d conteneur(s) up%s' "$G" "$up" "$Z"
    [ "${down:-0}" -gt 0 ] && printf '  %s%d down%s' "$M" "$down" "$Z"
  else
    printf '%s%d conteneur(s) up%s  %s(lab à monter : hotel-lab/docker compose up -d)%s' "$R" "$up" "$Z" "$M" "$Z"
  fi
  return 0
}

# --- config : DÉCLARÉ (lu en JSONC, commentaires // et /* */ retires) ---------
cfg_read() {
  python3 - "$CFG" "$1" <<'PY' 2>/dev/null || printf '?'
import json, re, sys

path, key = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)      # commentaires de bloc
src = re.sub(r"(^|\s)//.*$", "", src, flags=re.M)      # commentaires de ligne
try:
    cfg = json.loads(src)
except Exception:
    print("?"); raise SystemExit
if key == "mcp":
    print(len(cfg.get("mcp") or {}))
else:
    print(cfg.get(key, "?"))
PY
}

main() {
  [ "${RT_HACK_BANNER_ONLY:-0}" = "1" ] && return 0
  banner
  printf '  %sagent pentest · doctrine ROE fail-closed · affichage = mesure uniquement%s\n\n' "$D" "$Z"

  # Les deux mesures lentes partent en parallèle, l'ordre d'affichage est fixe.
  local tmp; tmp=$(mktemp -d)
  egress_line   > "$tmp/egress"      & local p_e=$!
  engagement_line > "$tmp/engagement" & local p_g=$!
  wait "$p_e" "$p_g" 2>/dev/null

  printf '  %sMESURÉ%s\n' "$R" "$Z"
  kv "hôte"       "$(hostname 2>/dev/null) · $(date -u '+%Y-%m-%d %H:%M:%SZ') · tty=$(tty 2>/dev/null | sed 's|/dev/||')"
  kv "egress"     "$(cat "$tmp/egress")"
  kv "engagement" "$(cat "$tmp/engagement")"
  kv "lab docker" "$(lab_line)"
  rm -rf "$tmp"

  printf '\n  %sDÉCLARÉ%s  %s(config projet — pas une mesure d etat)%s\n' "$R" "$Z" "$M" "$Z"
  kv "modèle"     "$(cfg_read model)"
  kv "agent"      "$(cfg_read default_agent)"
  kv "mcp"        "$(cfg_read mcp) déclarés"
  printf '\n'
}

main "$@"
