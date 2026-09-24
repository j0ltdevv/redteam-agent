#!/usr/bin/env bash
# vpn-up.sh — monte le VPN hôte avec un protocole robuste (hotspot mobile)
# et vérifie l'egress AVANT de te laisser partir sur une cible.
#
# Pourquoi ce script existe : sur un hotspot iOS/4G, WireGuard (UDP) perd ses
# handshakes et Windscribe coupe le tunnel toutes les 3-5 min
# (« Time since last handshake time exceeded 3 minutes, disconnecting » dans
# /var/log/windscribe/helper.log). Le DNS du tunnel (10.255.255.1) devient alors
# injoignable -> « rien ne marche ». `stealth` encapsule OpenVPN dans du TLS 443
# (wstunnel) : ça passe hotspots et CGNAT.
#
# Usage :
#   ./scripts/vpn-up.sh              # stealth (défaut, le plus robuste)
#   ./scripts/vpn-up.sh tcp:443      # OpenVPN TCP (plus rapide, correcte sur hotspot)
#   ./scripts/vpn-up.sh wireguard    # seulement si tu es sur une Wi-Fi normale
#   ./scripts/vpn-up.sh --check      # ne connecte RIEN, affiche l'état + l'IP
#   ./scripts/vpn-up.sh --diagnose   # ne connecte RIEN, diagnostic approfondi
#   ./scripts/vpn-up.sh --help
#
# Codes de retour :
#   0 = tunnel connecté ET egress vérifié (ou --check/--diagnose propre)
#   1 = pas connecté (--check/--diagnose) ou échec de connexion
#   2 = tunnel connecté mais EGRESS NON VÉRIFIÉ -> ne pas lancer d'engagement
#
# Le script ne connecte rien sans que TU le demandes : --check et --diagnose
# sont strictement en lecture seule.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/vpn_state.sh"

WS_LOG="${WS_LOG:-/var/log/windscribe/helper.log}"
PROTO="stealth"
CHECK_ONLY=0
DIAGNOSE=0

usage() {
    cat <<'USAGE'
vpn-up.sh — monte le tunnel VPN hôte et VÉRIFIE l'egress avant de te laisser partir.

  ./scripts/vpn-up.sh [protocole]   connecte (stealth par défaut | tcp:443 | wireguard)
  --check        état + IP courante, ne connecte rien (lecture seule)
  --diagnose     DNS, route, pare-feu, protocole, IP (lecture seule)
  --help         ce message

Retour : 0 = connecté + egress vérifié ; 1 = non connecté / échec ;
2 = connecté mais egress NON vérifié (fail-closed : pas d'engagement).
USAGE
}

for arg in "$@"
do
    case "$arg" in
        --check)    CHECK_ONLY=1 ;;
        --diagnose) DIAGNOSE=1 ;;
        --help|-h)  usage; exit 0 ;;
        -*)         echo "[vpn] flag inconnu: $arg (voir --help)" >&2; exit 2 ;;
        *)          PROTO="$arg" ;;
    esac
done

# --- IP de sortie : 1er essai via DNS, 2e sans DNS --------------------------
# Pourquoi sans DNS : en mode stealth Windscribe ne pousse pas de resolver
# (aucune ligne setDnsServers dans helper.log pour une session protocol 2) et le
# pare-feu bloque le reste -> "curl https://api.ipify.org" échoue alors que le
# tunnel monte bien (d'où le "?" observé). Cloudflare a un certificat pour
# 1.1.1.1 : https://1.1.1.1/cdn-cgi/trace donne l'IP sortante sans résolution.
fetch_egress_ip() {
    local ip
    ip="$(curl -s --max-time 12 https://api.ipify.org 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$ip" ] && [ "$ip" != "?" ]; then
        printf '%s\n' "$ip"
        return 0
    fi
    ip="$(curl -s --max-time 12 https://1.1.1.1/cdn-cgi/trace 2>/dev/null \
          | sed -n 's/^ip=//p' | tr -d '[:space:]')"
    if [ -n "$ip" ]; then
        printf '%s\n' "$ip"
        return 0
    fi
    return 1
}

# Le tunnel juste monté met un moment à passer DNS+TLS : on réessaie.
verify_egress() {
    local attempt
    for attempt in 1 2 3
    do
        if EGRESS_IP="$(fetch_egress_ip)"; then
            return 0
        fi
        sleep 2
    done
    EGRESS_IP=""
    return 1
}

firewall_state() {
    windscribe-cli status 2>/dev/null \
        | grep -E 'pare-feu|irewall' | head -n 1 \
        | sed 's/.*: *//' || echo "?"
}

# Dernier protocole réellement monté (3 = WireGuard/UDP, 2 = stealth/wstunnel).
last_protocol() {
    grep -aoE 'isConnected: true, protocol: [0-9]+' "$WS_LOG" 2>/dev/null \
        | tail -n 1 | grep -oE '[0-9]+$' || echo "?"
}

report_protocol_risk() {
    local proto
    proto="$(last_protocol)"
    case "$proto" in
        3)  if [ "$PROTO" = "wireguard" ] && [ "$CHECK_ONLY" = "0" ]; then
                echo "[vpn] ATTENTION: protocole monté = WireGuard (UDP) — sur un hotspot"
                echo "[vpn]            mobile il va lâcher toutes les 3-5 min. Préfère stealth."
            fi ;;
        "?") : ;;
        *)  echo "[vpn] protocole monté: $proto (2 = stealth/wstunnel, 3 = wireguard)" ;;
    esac
}

diagnose() {
    echo "[vpn] --- diagnostic ---"
    if getent hosts api.ipify.org >/dev/null 2>&1; then
        echo "[vpn]   DNS     : ok ($(getent hosts api.ipify.org | head -n 1 | awk '{print $1}'))"
    else
        echo "[vpn]   DNS     : KO (api.ipify.org non résoluble) — cause probable du '?'"
    fi
    echo "[vpn]   DNS cfg : $(resolvectl status 2>/dev/null | grep -E 'DNS Servers:' | head -n 2 | tr '\n' ';' | tr -s ' ')"
    echo "[vpn]   route   : $(ip route get 1.1.1.1 2>/dev/null | head -n 1)"
    echo "[vpn]   pare-feu: $(firewall_state)"
    echo "[vpn]   proto   : $(last_protocol) (2 = stealth/wstunnel, 3 = wireguard/UDP)"
    echo "[vpn]   IP      : $(fetch_egress_ip 2>/dev/null || echo 'NON VÉRIFIÉE')"
}

if rt_vpn_up; then
    if verify_egress; then
        echo "[vpn] déjà connecté — IP de sortie: $EGRESS_IP"
        echo "[vpn] pare-feu: $(firewall_state)"
        report_protocol_risk
        if [ "$DIAGNOSE" = "1" ]; then diagnose; fi
        exit 0
    fi
    echo "[vpn] connecté mais EGRESS NON VÉRIFIÉ" >&2
    diagnose
    echo "[vpn] FAIL-CLOSED: ne lance pas d'engagement tant que l'IP sortante n'est pas prouvée." >&2
    exit 2
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo "[vpn] NON connecté — IP actuelle: $(fetch_egress_ip 2>/dev/null || echo '?')"
    echo "[vpn] pare-feu: $(firewall_state)"
    echo "[vpn] pour te connecter: ./scripts/vpn-up.sh [stealth|tcp:443|wireguard]"
    exit 1
fi

if [ "$DIAGNOSE" = "1" ]; then
    echo "[vpn] NON connecté (mode diagnostic, lecture seule)"
    diagnose
    exit 1
fi

if ! command -v windscribe-cli >/dev/null 2>&1; then
    echo "[vpn] windscribe-cli absent" >&2
    exit 1
fi

echo "[vpn] connexion en mode '$PROTO' (stealth = TLS 443, survit aux hotspots mobiles)..."
timeout 90 windscribe-cli connect "$PROTO" >/dev/null 2>&1 || true

for _i in $(seq 1 45)
do
    if rt_vpn_up; then
        if verify_egress; then
            echo "[vpn] connecté — IP de sortie: $EGRESS_IP"
            echo "[vpn] pare-feu: $(firewall_state)"
            report_protocol_risk
            case "$(firewall_state)" in
                *ésactiv*|*isabled*)
                    echo "[vpn] ATTENTION: kill switch désarmé — si le tunnel lâche, ton trafic"
                    echo "[vpn]            repartira en direct depuis ton IP réelle." ;;
            esac
            exit 0
        fi
        echo "[vpn] tunnel monté mais IP de sortie NON vérifiée après 3 essais" >&2
        diagnose
        echo "[vpn] FAIL-CLOSED: déconnecte (windscribe disconnect) puis relance avec" >&2
        echo "[vpn]            tcp:443, ou regarde: sudo tail -n 30 $WS_LOG" >&2
        exit 2
    fi
    sleep 1
done

echo "[vpn] ÉCHEC: tunnel non établi après 45 s — regarde:" >&2
echo "[vpn]   sudo tail -n 30 $WS_LOG" >&2
exit 1
