#!/usr/bin/env bash
# lib/vpn_state.sh — état d'egress partagé (VPN hôte par défaut, Tor en opt-in).
#
# Sourcé par tor-wrap.sh, tor-socks5-wrap.sh et egress-wrap.sh pour éviter de
# dupliquer la logique d'état réseau. Aucun side-effect : uniquement des
# fonctions de lecture + deux messages d'erreur normalisés.

# rt_vpn_up — vrai si le tunnel Windscribe est connecté.
# `windscribe-cli status` affiche DEUX lignes "État de connexion" : la première
# décrit le compte/daemon (toujours "Connecté" quand l'app tourne), la dernière
# décrit le tunnel. On ne lit que la dernière — sinon un VPN coupé passerait
# pour connecté (faux positif = fuite).
rt_vpn_up() {
    command -v windscribe-cli >/dev/null 2>&1 || return 1
    local st tunnel
    st="$(windscribe-cli status 2>/dev/null || true)"
    tunnel="$(printf '%s\n' "$st" | grep -E 'tat de connexion|Connection state' | tail -n 1)"
    case "$tunnel" in
        *[Cc]oupé*|*[Dd]isconnected*) return 1 ;;
        *[Cc]onnecté*|*[Cc]onnected*) return 0 ;;
        *) return 1 ;;
    esac
}

# rt_tor_up — vrai si un proxy Tor répond (gateway docker ou 9050 sur l'hôte).
rt_tor_up() {
    if command -v docker >/dev/null 2>&1 \
        && docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^redteam-tor-gateway$"
    then
        return 0
    fi
    if command -v ss >/dev/null 2>&1; then
        if ss -lnt 2>/dev/null | grep -q ":9050"; then
            return 0
        fi
    fi
    return 1
}

# rt_egress_mode — "tor" si RT_USE_TOR=1, sinon "vpn" (défaut).
rt_egress_mode() {
    if [ "${RT_USE_TOR:-0}" = "1" ]; then
        echo tor
    else
        echo vpn
    fi
}

# rt_allow_direct — vrai si l'opérateur a explicitement accepté la sortie directe.
rt_allow_direct() {
    [ "${RT_ALLOW_DIRECT:-0}" = "1" ]
}

# rt_warn_direct — avertissement commun pour le bypass explicite.
rt_warn_direct() {
    echo "[egress] WARNING: no VPN detected, RT_ALLOW_DIRECT=1 set, running WITHOUT egress isolation" >&2
}

# rt_refuse — refus fail-closed commun.
rt_refuse() {
    echo "[egress] ERROR: no VPN connection detected (windscribe-cli status: tunnel down)" >&2
    echo "[egress] ERROR: connect the VPN (windscribe-cli connect) or set RT_ALLOW_DIRECT=1 explicitly" >&2
}
