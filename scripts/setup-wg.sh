#!/usr/bin/env bash
# setup-wg.sh — installe un profil WireGuard manuel (Windscribe) + kill-switch nftables.
#
# Contourne le daemon windscribe-cli 2.21.7 (tunnel qui ne monte jamais) en
# utilisant wg-quick directement. Le tunnel kernel wg0 créé ici est détecté
# par scripts/lib/vpn_state.sh et fait passer verify-vpn au vert.
#
# Usage:
#   bash scripts/setup-wg.sh install <profil.conf> [nom]  # installe le profil (root via sudo demandé)
#   bash scripts/setup-wg.sh up [nom]                     # monte le tunnel + kill-switch
#   bash scripts/setup-wg.sh down [nom]                   # démonte le tunnel
#   bash scripts/setup-wg.sh status [nom]                 # état du tunnel (wg show)
#   bash scripts/setup-wg.sh killswitch on|off            # kill-switch nftables on/off
#
# Prérequis: wireguard-tools (installé), profil .conf téléchargé depuis
# windscribe.com (connecté → Setup → WireGuard) déposé côté utilisateur.
set -euo pipefail

WG_NAME="${2:-redteam}"
WG_CONF="/etc/wireguard/${WG_NAME}.conf"
NFT_TABLE="redteam-killswitch"

banner() { echo "=== setup-wg ($WG_NAME) ==="; }

die() { echo "[X] $*" >&2; exit 1; }
ok()  { echo "[OK] $*"; }
info(){ echo "[..] $*"; }

need_root() {
  [[ $EUID -eq 0 ]] || die "cette commande requiert root (relance avec sudo)"
}

cmd_install() {
  need_root
  local src="${1:?usage: setup-wg.sh install <profil.conf> [nom]}"
  [[ -f "$src" ]] || die "profil introuvable: $src"

  # Sanity checks du profil
  grep -q '^\[Interface\]' "$src" || die "pas de section [Interface] — ce n'est pas un profil WireGuard"
  grep -q 'PrivateKey' "$src" || die "pas de PrivateKey dans le profil"
  grep -q '^\[Peer\]' "$src" || die "pas de section [Peer] — endpoint manquant"
  info "profil valide (Interface + Peer + PrivateKey)"

  install -m 600 "$src" "$WG_CONF"
  ok "profil installé: $WG_CONF (perms 600)"

  # Ensure DNS via tunnel (post-up wg-quick gère resolvectl si dns = défini)
  grep -q '^DNS' "$WG_CONF" || {
    echo "DNS = 10.255.255.254" >> "$WG_CONF"
    info "DNS Windscribe ajouté (10.255.255.254)"
  }

  echo ""
  echo "Prochaine étape:  sudo bash scripts/setup-wg.sh up"
}

cmd_up() {
  need_root
  [[ -f "$WG_CONF" ]] || die "profil absent: $WG_CONF (install d'abord)"
  info "montage du tunnel $WG_NAME..."
  wg-quick up "$WG_NAME"
  ok "tunnel monté"
  cmd_killswitch on
  wg show "$WG_NAME"
  echo ""
  info "validation egress: cd ~/redteam-agent && ./start-redteam.sh verify-vpn"
}

cmd_down() {
  need_root
  cmd_killswitch off || true
  wg-quick down "$WG_NAME" && ok "tunnel démonté" || warn_down
}
warn_down() { info "tunnel déjà absent"; }

cmd_status() {
  if [[ -f "$WG_CONF" ]] && ip link show "$WG_NAME" &>/dev/null; then
    ok "tunnel $WG_NAME actif:"
    wg show "$WG_NAME"
  else
    info "tunnel $WG_NAME absent"
  fi
  local exit_ip org
  exit_ip=$(curl -4 -s --max-time 5 https://ipinfo.io/ip || true)
  org=$(curl -4 -s --max-time 5 https://ipinfo.io/org || true)
  echo "IP de sortie: ${exit_ip:-injoignable} ${org:+[$org]}"
}

cmd_killswitch() {
  need_root
  local mode="${1:?usage: killswitch on|off}"
  case "$mode" in
    on)
      local endpoint
      endpoint=$(grep -oP '^Endpoint\s*=\s*\K[^:]+(:[0-9]+)?' "$WG_CONF" | head -1)
      [[ -n "$endpoint" ]] || die "endpoint introuvable dans $WG_CONF"
      local port="${endpoint##*:}"
      port="${port:-51820}"
      local fwmark
      fwmark=$(grep -oP '^FwMark\s*=\s*\K[0-9]+' "$WG_CONF" | head -1)
      fwmark="${fwmark:-51820}"

      nft delete table ip "$NFT_TABLE" 2>/dev/null || true
      nft -f - <<NFT
table ip $NFT_TABLE {
  set endpoint {
    type ipv4_addr
    flags interval
    elements = { $(grep -oP '^Endpoint\s*=\s*\K[0-9.]+' "$WG_CONF" | head -1) }
  }
  chain out {
    type filter hook output priority 0; policy drop;
    oif "lo" accept
    oifname != "lo" ip daddr @endpoint accept
    oifname != "lo" udp dport $port accept
    ct state established,related accept
    ip daddr 192.168.0.0/16 accept
    ip daddr 10.0.0.0/8 accept
    ip daddr 172.16.0.0/12 accept
    oifname "$WG_NAME" accept
  }
}
NFT
      ok "kill-switch armé (tout le trafic sort par $WG_NAME, sauf endpoint + LAN)"
      ;;
    off)
      nft delete table ip "$NFT_TABLE" 2>/dev/null && ok "kill-switch désarmé" || info "kill-switch déjà absent"
      ;;
    *) die "usage: killswitch on|off" ;;
  esac
}

banner
case "${1:-}" in
  install)    shift; cmd_install "$@" ;;
  up)         [[ $# -ge 1 ]]; cmd_up ;;
  down)       cmd_down ;;
  status)     cmd_status ;;
  killswitch) shift; cmd_killswitch "$@" ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
