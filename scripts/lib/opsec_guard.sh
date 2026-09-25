#!/usr/bin/env bash
# scripts/lib/opsec_guard.sh — source unique du controle d'isolation d'egress.
#
# Pourquoi ce fichier existe : les wrappers Fail-closed (egress-wrap.sh,
# tor-socks5-wrap.sh, tor-wrap.sh) demandaient « un tunnel est-il monte ? ».
# Cette question a une reponse VRAIE sans preuve du routage : c'est exactement
# le piege qui a fait croire « connecte » pendant que le trafic sortait en clair
# (cf. SETUP_WG.md : « le daemon annonce Connecte mais AUCUN tunnel actif »).
#
# Ici on ne demande plus « le tunnel est-il monte ? » mais « par ou sort
# reellement mon trafic ? », repondu par une MESURE : l'IP de sortie vue par le
# processus, comparee a l'IP directe de la machine.
#
# Verdict possible :
#   bulle     -> on est dans le namespace "pentest" (trafic 100% tunnel)   OK
#   tunnel    -> hors bulle, mais l'IP de sortie != IP directe               OK
#   CLAIR     -> l'IP de sortie == IP directe : FUITE, refus               BLOQUE
#   INCONNU   -> impossible de mesurer                                      BLOQUE
#
# Aucun side-effect au chargement : uniquement des fonctions de lecture.

# rt_og_in_bubble — vrai si CE processus tourne dans la bulle reseau isolee.
# On compare le netns du processus a un netws nomme via `ip netns identify $$`.
# NE PAS utiliser `ip netns list | grep pentest` : cela liste les netns EXISTANTS
# sur la machine, pas celui du processus courant (faux positif des que la bulle
# est montee, meme depuis le PC hote).
rt_og_in_bubble() {
    [ "${RT_BUBBLE:-0}" = "1" ] && return 0
    command -v ip >/dev/null 2>&1 || return 1
    ip netns identify $$ 2>/dev/null | grep -qx pentest
}

# rt_og_direct_ip — IP publique DIRECTE de la machine (jamais par le VPN).
# Ecrit par `pentest-vpn up` et `pentest-vpn-refresh` dans /run/pentest-vpn/.
rt_og_direct_ip() {
    tr -d '[:space:]' < /run/pentest-vpn/host-egress-ip 2>/dev/null
}

# rt_og_exit_ip — IP publique vue par CE processus (donc par le routage actif).
rt_og_exit_ip() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null | tr -d '[:space:]'
}

# rt_og_exit_ip6 — IPv6 de sortie (vide = pas d'IPv6, donc pas de fuite IPv6).
rt_og_exit_ip6() {
    command -v curl >/dev/null 2>&1 || return 0
    curl -6 -s --max-time 8 https://api64.ipify.org 2>/dev/null | tr -d '[:space:]'
}

# rt_og_is_cleartext — vrai si le trafic partirait en clair (mesure, pas supposition).
rt_og_is_cleartext() {
    local direct exit
    direct="$(rt_og_direct_ip)"
    exit="$(rt_og_exit_ip)"
    [ -n "$direct" ] && [ -n "$exit" ] && [ "$direct" = "$exit" ]
}

# rt_og_verdict — "bulle" | "tunnel" | "CLAIR" | "INCONNU"
rt_og_verdict() {
    if rt_og_in_bubble; then echo "bulle"; return 0; fi
    if rt_og_is_cleartext; then echo "CLAIR"; return 1; fi
    if command -v rt_vpn_up >/dev/null 2>&1 && rt_vpn_up 2>/dev/null; then
        echo "tunnel"; return 0
    fi
    echo "INCONNU"; return 1
}

# rt_og_report — tableau lisible, utilise par opsec-check.sh
rt_og_report() {
    printf '  dans la bulle      : %s\n' "$(rt_og_in_bubble && echo OUI || echo non)"
    printf '  IP directe (hote)  : %s\n' "$(rt_og_direct_ip || echo inconnue)"
    printf '  IP de sortie       : %s\n' "$(rt_og_exit_ip || echo injoignable)"
    printf '  sortie IPv6        : %s\n' "$(rt_og_exit_ip6 || echo 'aucune (pas de fuite IPv6)')"
    printf '  tunnel detecte     : %s\n' "$(command -v rt_vpn_up >/dev/null 2>&1 && (rt_vpn_up 2>/dev/null && echo OUI || echo non) || echo 'n/a')"
    printf '  VERDICT            : %s\n' "$(rt_og_verdict)"
}

# rt_og_require_isolated — garde-fou fail-closed appele par les wrappers.
# 0 = isolation prouvee (bulle ou tunnel), 1 = refus.
rt_og_require_isolated() {
    case "$(rt_og_verdict)" in
        bulle|tunnel) return 0 ;;
        CLAIR)
            echo "[opsec] REFUS : le trafic partirait EN CLAIR depuis ton IP directe ($(rt_og_direct_ip))." >&2
            echo "[opsec] Lance l'engagement dans la bulle : redteam-bubble <commande>" >&2
            echo "[opsec] (montage : sudo pentest-vpn up)" >&2
            return 1 ;;
        *)
            echo "[opsec] REFUS : impossible de prouver l'isolation d'egress (IP de sortie injoignable," >&2
            echo "[opsec]         pas de reference d'IP directe, ou pas de tunnel)." >&2
            echo "[opsec] Lance dans la bulle : redteam-bubble <commande>" >&2
            return 1 ;;
    esac
}
