#!/usr/bin/env bash
# =============================================================================
#  install.sh — installe les outils de la bulle VPN (idempotent)
#
#  AUCUNE cle privee n'est versionnee : /etc/pentest-vpn/wg.conf et
#  params.env sont crees localement (voir README.md, « config WireGuard »).
#
#  Usage : sudo bash bubble/install.sh
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "root requis : sudo bash bubble/install.sh"; exit 1; }

install -d -m 755 /usr/local/lib/pentest-shims
install -m 755 "$HERE/pentest-vpn"         /usr/local/sbin/pentest-vpn
install -m 755 "$HERE/pentest-vpn-refresh" /usr/local/sbin/pentest-vpn-refresh
install -m 755 "$HERE/pentest-shell"       /usr/local/bin/pentest-shell
install -m 755 "$HERE/redteam-bubble"      /usr/local/bin/redteam-bubble
install -m 755 "$HERE/shims/wg"            /usr/local/lib/pentest-shims/wg

echo "installe :"
echo "  sudo pentest-vpn up          monter la bulle (config WG requise)"
echo "  pentest-shell                entrer dans la bulle"
echo "  redteam-bubble verify-vpn    controle d'egress du framework"
echo
if [ -f /etc/pentest-vpn/wg.conf ]; then
  echo "config WG presente : /etc/pentest-vpn/wg.conf"
else
  echo "CONFIG WG ABSENTE : /etc/pentest-vpn/wg.conf — voir bubble/README.md"
  echo "  (genere via protonvpn/windscribe puis sudo pentest-vpn-refresh)"
fi
