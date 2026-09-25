#!/usr/bin/env bash
# lib/vpn_state.sh — état d'egress partagé (VPN hôte par défaut, Tor en opt-in).
#
# Sourcé par tor-wrap.sh, tor-socks5-wrap.sh, egress-wrap.sh et start-redteam.sh.
# Aucun side-effect au chargement : uniquement des fonctions de lecture.
#
# Historique 2026-09-24 : `windscribe-cli status` affiche DEUX lignes
# "État de connexion" (la première = compte/daemon, toujours "Connecté") ;
# le faux positif a fait croire à un VPN actif alors que le trafic sortait en
# clair sur Free Mobile (IP 37.165.58.164 + IPv6 wlan0). La détection est donc
# désormais multi-signaux et fail-closed :
#   1. la DERNIÈRE ligne "État de connexion" du CLI (état tunnel) ;
#   2. une PREUVE matérielle de tunnel (iface tun/wg/ppp up, ou xfrm IPsec) ;
#   3. optionnel : l'IP de sortie via HTTPS (utilisée par verify-vpn).
# Échappatoire explicite : RT_VPN_TRUST_CLI=1 ignore la preuve matérielle.

# rt_tunnel_present — vrai si une interface de tunnel VPN est active sur l'hôte.
# Couvre : WireGuard (wg*), OpenVPN/stealth/wstunnel (tun*), le nommage BSD
# de Windscribe (utun* — constaté en réel : utun420), PPP (ppp*), IKEv2/IPsec
# (SAD xfrm non vide, interfaces ipsec*). Ignore virbr/docker/veth/lo.
rt_tunnel_present() {
    command -v ip >/dev/null 2>&1 || return 1
    if ip -o link show 2>/dev/null | awk -F': ' '{print $2}' \
        | grep -Eq '^(tun|utun|wg|ppp|ipsec)[0-9]+'; then
        return 0
    fi
    if [ -n "$(ip xfrm state 2>/dev/null | head -n 1)" ]; then
        return 0
    fi
    return 1
}

# rt_cli_tunnel_connected — l'état tunnel selon la DERNIÈRE ligne du CLI.
rt_cli_tunnel_connected() {
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

# rt_wg_manual_up — tunnel wg-quick manuel actif (setup-wg.sh) avec handshake récent.
# Preuve matérielle suffisante : l'iface existe ET la dernière handshake avec
# le peer date de < 3 min (un tunnel sans handshake ne route rien).
rt_wg_manual_up() {
    command -v wg >/dev/null 2>&1 || return 1
    command -v ip >/dev/null 2>&1 || return 1
    ip -o link show 2>/dev/null | awk -F': ' '{print $2}' \
        | grep -Eq '^wg[0-9]+$' || return 1
    # au moins un peer avec un handshake < 180 s
    # CORRIGE (2026-09-25) : `wg show all latest-handshakes` sort
    #   "<iface>\t<pubkey>\t<timestamp>"
    # -> le timestamp est en $3. La version precedente lisait $2 (la cle
    # publique du peer, evaluee a 0 en numerique) : le test etait donc
    # TOUJOURS faux et rt_wg_manual_up ne pouvait jamais renvoyer true. Un
    # tunnel wg-quick parfaitement monte etait declare absent (verify-vpn
    # rouge, egress-wrap.sh fail-closed). On accepte les deux formats.
    if wg show all latest-handshakes 2>/dev/null \
        | awk '{ ts = ($3 != "" ? $3 : $2); if (ts + 0 > 0 && systime() - ts < 180) found = 1 } END { exit !found }'
    then
        return 0
    fi
    # Repli fonctionnel. WireGuard ne renegocie que SOUS trafic : apres ~3 min
    # d'inactivite le handshake est « perime » alors que le tunnel est
    # parfaitement utilisable (le premier paquet relance la negociation).
    # Sans ce repli, un tunnel sain est declare absent : egress-wrap.sh refuse
    # alors que tout passe — constate sur la bulle pentest au montage.
    rt_wg_probe
}

# rt_wg_probe — sondage fonctionnel du tunnel, SANS DNS (7 s max).
# Seulement si un wg* porte la route par defaut : sinon le sondage prouverait
# le chemin physique, pas le tunnel.
rt_wg_probe() {
    ip route show default 2>/dev/null | grep -Eq 'dev wg[0-9]+' || return 1
    if command -v ping >/dev/null 2>&1 && ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        return 0
    fi
    if command -v curl >/dev/null 2>&1 \
        && timeout 5 curl -4 -s -o /dev/null --max-time 4 http://1.1.1.1 2>/dev/null; then
        return 0
    fi
    return 1
}

# --- Bulle reseau isolee "pentest" (pentest-vpn) -----------------------------
# rt_in_bubble — vrai si le processus tourne DANS la bulle reseau isolee.
rt_in_bubble() {
    [ "${RT_BUBBLE:-0}" = "1" ] && return 0
    command -v ip >/dev/null 2>&1 || return 1
    ip netns list 2>/dev/null | grep -qw pentest
}

# rt_bubble_host_ip — IP publique directe de l'hote, relevee par `pentest-vpn up`.
# Reference d'isolation : dans la bulle, une IP de sortie differente de celle-ci
# prouve que le trafic passe bien par le tunnel (wg0 est l'unique route par defaut).
# /run d'abord : lisible par l'utilisateur ; /etc/pentest-vpn est en 700 (cle privee).
rt_bubble_host_ip() {
    local f
    for f in /run/pentest-vpn/host-egress-ip /etc/pentest-vpn/host-egress-ip; do
        if [ -r "$f" ]; then
            tr -d '[:space:]' < "$f"
            return 0
        fi
    done
    return 1
}

# rt_vpn_up — vrai si le tunnel VPN est VRAIMENT connecté, par l'un des moyens :
#   1. tunnel wg-quick manuel actif (setup-wg.sh) → preuve matérielle suffisante
#   2. chemin Windscribe : état tunnel CLI positif ET preuve matérielle
#      (iface/xfrm), sauf RT_VPN_TRUST_CLI=1 (échappatoire, diagnostic seulement).
rt_vpn_up() {
    if rt_wg_manual_up; then
        return 0
    fi
    rt_cli_tunnel_connected || return 1
    if [ "${RT_VPN_TRUST_CLI:-0}" = "1" ]; then
        return 0
    fi
    rt_tunnel_present
}

# rt_exit_ip — IP publique IPv4 de sortie via HTTPS (10 s max). Vide en échec.
rt_exit_ip() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null
}

# rt_exit_ip6 — IP publique IPv6 de sortie via HTTPS. Vide si pas d'IPv6.
rt_exit_ip6() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -6 -s --max-time 10 https://api64.ipify.org 2>/dev/null
}

# rt_exit_ip_org — organisme propriétaire de l'IPv4 de sortie (ipinfo.io).
rt_exit_ip_org() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -4 -s --max-time 10 "https://ipinfo.io/$(rt_exit_ip)/json" 2>/dev/null \
        | python3 -c 'import sys,json;print(json.load(sys.stdin).get("org",""))' 2>/dev/null
}

# rt_ipv6_leak — vrai si l'IPv6 publique ne passe PAS par un tunnel VPN
# (préfixe hérité d'une iface physique = fuite dès que le site a un AAAA).
rt_ipv6_leak() {
    local ip6
    ip6="$(rt_exit_ip6)" || return 1
    [ -z "$ip6" ] && return 1   # pas d'IPv6 du tout = pas de fuite IPv6 possible
    command -v ip >/dev/null 2>&1 || return 1
    local pfx
    pfx="${ip6%%:*}"
    if ip -o addr show scope global 2>/dev/null \
        | grep -vE ' (lo|virbr|docker|veth|br-|wg|tun|ppp)' \
        | grep -qE "inet6 ${pfx}[0-9a-f]*:"; then
        return 0   # le préfixe de sortie est porté par une iface physique → fuite
    fi
    return 1
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

# rt_refuse — refus fail-closed commun (détaille le signal manquant).
rt_refuse() {
    echo "[egress] ERROR: no VPN connection detected" >&2
    if rt_cli_tunnel_connected && ! rt_tunnel_present; then
        echo "[egress] ERROR: windscribe-cli annonce Connected mais AUCUN tunnel actif (faux état CLI connu)" >&2
        echo "[egress] ERROR: reconnecte proprement : windscribe-cli disconnect && windscribe-cli connect" >&2
    else
        echo "[egress] ERROR: connect the VPN (windscribe-cli connect) or set RT_ALLOW_DIRECT=1 explicitly" >&2
    fi
}
