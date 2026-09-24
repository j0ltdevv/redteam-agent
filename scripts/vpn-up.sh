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
#
# Le script ne connecte rien sans que TU le demandes : `--check` est en lecture seule.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/vpn_state.sh"

WS_LOG="${WS_LOG:-/var/log/windscribe/helper.log}"
PROTO="stealth"
CHECK_ONLY=0

for arg in "$@"
do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        -*)      echo "[vpn] flag inconnu: $arg" >&2; exit 2 ;;
        *)       PROTO="$arg" ;;
    esac
done

egress_ip() {
    curl -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "?"
}

firewall_state() {
    windscribe-cli status 2>/dev/null \
        | grep -E 'pare-feu|irewall' | head -n 1 \
        | sed 's/.*: *//' || echo "?"
}

# Dernier protocole réellement monté (3 = WireGuard/UDP, 2 = stealth/wstunnel).
last_protocol() {
    grep -aoE '"isConnected: true, protocol: [0-9]+"' "$WS_LOG" 2>/dev/null \
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

if rt_vpn_up; then
    echo "[vpn] déjà connecté — IP de sortie: $(egress_ip)"
    echo "[vpn] pare-feu: $(firewall_state)"
    report_protocol_risk
    exit 0
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo "[vpn] NON connecté — IP actuelle: $(egress_ip)"
    echo "[vpn] pare-feu: $(firewall_state)"
    echo "[vpn] pour te connecter: ./scripts/vpn-up.sh [stealth|tcp:443|wireguard]"
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
        echo "[vpn] connecté — IP de sortie: $(egress_ip)"
        echo "[vpn] pare-feu: $(firewall_state)"
        report_protocol_risk
        case "$(firewall_state)" in
            *ésactiv*|*isabled*)
                echo "[vpn] ATTENTION: kill switch désarmé — si le tunnel lâche, ton trafic"
                echo "[vpn]            repartira en direct depuis ton IP réelle." ;;
        esac
        exit 0
    fi
    sleep 1
done

echo "[vpn] ÉCHEC: tunnel non établi après 45 s — regarde:" >&2
echo "[vpn]   sudo tail -n 30 $WS_LOG" >&2
exit 1
