#!/usr/bin/env bash
# ============================================================================
#  opsec-check.sh — etat OPSEC d'egress, PAR MESURE.
#
#  Repond a la seule question qui compte avant un engagement :
#  « par ou sort reellement mon trafic ? » — en comparant l'IP de sortie vue par
#  ce processus a l'IP directe de la machine.
#
#      CLAIR      -> fuite : le trafic sort en clair. Engagement INTERDIT.
#      INCONNU    -> non mesurable. Engagement INTERDIT (fail-closed).
#      tunnel     -> hors bulle mais routage par le tunnel. OK.
#      bulle      -> namespace "pentest" : trafic 100% tunnel. OK.
#
#  Usage : scripts/opsec-check.sh          # exit 0 si isole, 1 sinon
#  Env   : RT_BUBBLE=1  force le mode bulle (utilise par redteam-bubble)
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/vpn_state.sh" 2>/dev/null || true
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/opsec_guard.sh"

echo "▸ Controle OPSEC d'egress — $(date '+%F %T')"
rt_og_report

verdict="$(rt_og_verdict)"
echo
case "$verdict" in
    bulle)
        echo "  [OK]   isole : namespace pentest, le trafic sort par le tunnel." ;;
    tunnel)
        echo "  [OK]   isole : l'IP de sortie differe de l'IP directe (tunnel actif)." ;;
    CLAIR)
        echo "  [KO]   FUITE : le trafic sort en clair depuis ton IP directe." ;;
    *)
        echo "  [KO]   NON MESURABLE : fail-closed, on ne suppose rien." ;;
esac

if command -v curl >/dev/null 2>&1; then
  printf '\n  organisation (ipinfo) : '
  timeout 12 curl -4 -s --max-time 10 https://ipinfo.io/$(rt_og_exit_ip)/json 2>/dev/null \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("org","?"),d.get("country","?"))' 2>/dev/null \
    || echo 'injoignable'
fi

# 0 = isolation prouvee (bulle ou tunnel) ; 1 = CLAIR ou INCONNU (fail-closed).
[ "$verdict" = "bulle" ] || [ "$verdict" = "tunnel" ]
