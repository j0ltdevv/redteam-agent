#!/usr/bin/env bash
# ============================================================================
#  start-redteam.sh — Lancement tout-en-un de la stack RedTeam
#
#  1. Vérifie les pré-requis (Docker, Tor, opencode)
#  2. Démarre le daemon Tor hôte
#  3. Construit + démarre le conteneur redteam-tor-gateway
#  4. Vérifie toutes les images Docker
#  5. Protège .env (chmod 600)
#  6. Lance l’instance OpenCode Desktop isolée via start-redteam-desktop.sh
#  7. Ouvre le projet ~/redteam-agent dans son userData dédié
#
#  Usage:
#    ./start-redteam.sh          → lance tout
#    ./start-redteam.sh stop     → arrête la stack Tor + conteneurs
#    ./start-redteam.sh status   → affiche l'état
#    ./start-redteam.sh verify   → vérifie l'isolation Tor
#    ./start-redteam.sh verify-vpn → contrôle egress VPN (IP/org, fuite IPv6, kill-switch)
# ============================================================================
set -euo pipefail

REDTEAM_DIR="$HOME/redteam-agent"
DOCKER_DIR="$REDTEAM_DIR/docker"

# --- Couleurs ----------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

banner() {
  echo -e "${RED}${BOLD}"
  cat << 'EOF'
  ██████╗ ███████╗████████╗██████╗  ██████╗ ████████╗███████╗██████╗ ███╗   ███╗
  ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
  ██████╔╝█████╗     ██║   ██████╔╝██║   ██║   ██║   █████╗  ██████╔╝██╔████╔██║
  ██╔══██╗██╔══╝     ██║   ██╔══██╗██║   ██║   ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║
  ██║  ██║███████╗   ██║   ██║  ██║╚██████╔╝   ██║   ███████╗██║  ██║██║ ╚═╝ ██║
  ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
EOF
  echo -e "${NC}"
}

# --- Helpers -----------------------------------------------------------------
ok()   { echo -e "  ${GREEN}[✓]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
fail() { echo -e "  ${RED}[✗]${NC} $1"; }
info() { echo -e "  ${CYAN}[*]${NC} $1"; }

port_up() { ss -tln 2>/dev/null | grep -q ":$1 "; }

# --- 0. Pré-requis -----------------------------------------------------------
check_prereqs() {
  echo -e "\n${BOLD}▸ Pré-requis${NC}"
  local ok_count=0
  for cmd in docker curl jq; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "$cmd trouvé"
      ok_count=$((ok_count+1))
    else
      fail "$cmd manquant — installer: sudo pacman -S $cmd"
      exit 1
    fi
  done
  # opencode
  if command -v opencode >/dev/null 2>&1; then
    ok "opencode trouvé"
  else
    warn "opencode non trouvé dans PATH — tentative quand même"
  fi
}

# --- 1. VPN hôte (Windscribe, kill-switch) -------------------------------------
# VPN-ONLY (2026-09-24) : Tor n'est plus la sortie par défaut (exits bloquées
# par les WAF). La sortie passe par Windscribe avec kill-switch ON.
# NE CONNECTE PAS : le script vérifie seulement. L'utilisateur connecte lui-même
# (windscribe-cli connect) — une connexion auto casserait sa session réseau.
# Durci (2026-09-25) : détection via scripts/lib/vpn_state.sh — état CLI
# (dernière ligne "État de connexion") ET preuve matérielle de tunnel
# (iface tun/wg/ppp ou xfrm). Le faux "Connecté" du CLI a déjà causé une
# fuite en clair (Free Mobile) ; en plus l'appartenance de l'IP de sortie à
# Windscribe est vérifiée. Cibles internet => fail-closed (voir main).
check_host_vpn() {
  echo -e "\n${BOLD}▸ VPN hôte (Windscribe)${NC}"
  if ! command -v windscribe-cli >/dev/null 2>&1; then
    warn "windscribe-cli absent — sortie non isolée"
    return 0
  fi
  # shellcheck source=/dev/null
  . "$REDTEAM_DIR/scripts/lib/vpn_state.sh"
  if rt_vpn_up; then
    local ip org
    ip=$(rt_exit_ip)
    org=$(rt_exit_ip_org)
    ok "VPN connecté (CLI + tunnel matériel) — IP de sortie: ${ip:-?}"
    case "$org" in
      *Windscribe*|*windscribe*) ok "IP de sortie bien chez Windscribe [$org]" ;;
      *Proton*|*proton*) ok "IP de sortie bien chez Proton [$org]" ;;
      "") warn "Propriétaire de l'IP non identifiable (ipinfo.io injoignable ?)" ;;
      *) fail "IP de sortie = $org — CE N'EST NI Windscribe NI Proton (VPN mal routé)"
         return 1 ;;
    esac
  elif rt_cli_tunnel_connected; then
    fail "windscribe-cli annonce Connecté mais AUCUN tunnel actif (faux état CLI connu)"
    warn "Reconnexion propre : windscribe-cli disconnect && windscribe-cli connect"
    warn "(les scripts refuseront de tourner sans VPN, sauf RT_ALLOW_DIRECT=1)"
  else
    warn "VPN coupé — connecte-toi toi-même: windscribe-cli connect"
    warn "(les scripts refuseront de tourner sans VPN, sauf RT_ALLOW_DIRECT=1)"
  fi
  # Kill-switch : FirewallMode=Always (armé même VPN coupé) + FirewallWhen=Before Connection
  # dans ~/.config/Windscribe/windscribe_cli.conf.
  local ws_conf="$HOME/.config/Windscribe/windscribe_cli.conf"
  local fw_mode fw_when
  fw_mode=$(grep -E '^FirewallMode=' "$ws_conf" 2>/dev/null | cut -d= -f2 || true)
  fw_when=$(grep -E '^FirewallWhen=' "$ws_conf" 2>/dev/null | cut -d= -f2 || true)
  case "$fw_mode" in
    Always) ok "Kill-switch armé en permanence (FirewallMode=Always)" ;;
    Auto)   warn "Kill-switch armé seulement connecté (FirewallMode=Auto) — Always recommandé" ;;
    Off|"") warn "Kill-switch DÉSACTIVÉ (FirewallMode=${fw_mode:-absent}) — fuite possible hors VPN" ;;
    *)      warn "Kill-switch: FirewallMode=$fw_mode (inconnu)" ;;
  esac
  if [ -n "$fw_when" ]; then
    info "FirewallWhen=$fw_when"
  fi
}

# --- 2. Conteneur Tor gateway ------------------------------------------------
start_tor_gateway() {
  echo -e "\n${BOLD}▸ Conteneur Tor Gateway${NC}"

  # Build si image manquante
  if ! docker image inspect redteam-tor-gateway:latest >/dev/null 2>&1; then
    info "Construction de l'image redteam-tor-gateway..."
    (cd "$DOCKER_DIR" && docker compose build tor-gateway)
  fi

  # Démarrer si pas encore up
  if docker ps --format '{{.Names}}' | grep -q "^redteam-tor-gateway$"; then
    ok "redteam-tor-gateway déjà en cours"
  else
    info "Démarrage de redteam-tor-gateway..."
    (cd "$DOCKER_DIR" && docker compose up -d tor-gateway)

    # Vérifier le bootstrap Tor
    info "Attente du bootstrap Tor..."
    for i in $(seq 1 60); do
      if curl -s --socks5-hostname 127.0.0.1:9050 http://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; then
        local exit_ip
        exit_ip=$(curl -s --socks5-hostname 127.0.0.1:9050 http://check.torproject.org/api/ip 2>/dev/null | jq -r '.IP' 2>/dev/null || echo "?")
        ok "Tor bootstrapped — exit IP: $exit_ip"
        return 0
      fi
      sleep 1
    done
    warn "Bootstrap Tor timeout (60s) — le conteneur continue de démarrer"
  fi
}

# --- 3. Images Docker --------------------------------------------------------
check_images() {
  echo -e "\n${BOLD}▸ Images Docker${NC}"
  local missing=0
  for img in redteam-tor-gateway:latest kali-redteam:latest redteam-metasploit:latest projectdiscovery/katana:latest; do
    if docker image inspect "$img" >/dev/null 2>&1; then
      ok "$img"
    else
      fail "$img manquante"
      missing=$((missing+1))
    fi
  done
  # redteam-proxy est optionnel (pour mitmproxy)
  if docker image inspect redteam-proxy:latest >/dev/null 2>&1; then
    ok "redteam-proxy:latest (optionnel)"
  fi

  if [ "$missing" -gt 0 ]; then
    echo -e "\n  ${YELLOW}Pour builder les images manquantes:${NC}"
    echo "    cd $DOCKER_DIR && docker compose build"
  fi
}

# --- 4. Sécurité .env --------------------------------------------------------
check_env() {
  echo -e "\n${BOLD}▸ Sécurité .env${NC}"
  local env_file="$REDTEAM_DIR/.env"
  if [ -f "$env_file" ]; then
    local perms
    perms=$(stat -c '%a' "$env_file" 2>/dev/null || stat -f '%Lp' "$env_file" 2>/dev/null)
    if [ "$perms" = "600" ]; then
      ok ".env permissions: 600 (owner-only)"
    else
      warn ".env permissions: $perms → correction vers 600"
      chmod 600 "$env_file"
      ok ".env permissions corrigées"
    fi

    # Vérifier qu'il y a au moins les vars MSF
    if grep -q "MSF_USER" "$env_file" 2>/dev/null; then
      ok "Variables Metasploit présentes"
    else
      warn "Variables MSF manquantes dans .env"
    fi
  else
    warn ".env non trouvé dans $REDTEAM_DIR"
  fi
}

# --- Thème RedTeam -----------------------------------------------------------
# Le thème de l'instance daily ne doit jamais être modifié par ce script.
# Le launcher dédié passe par le profil XDG isolé ; le thème Desktop sera
# vérifié séparément, sans supposer que tui.json pilote le renderer Desktop.
activate_theme() {
  echo -e "\n${BOLD}▸ Thème OpenCode${NC}"
  warn "Le thème TUI daily n'est pas modifié ; l'instance Desktop dédiée conserve son profil isolé"
}

# --- 6. Réseau ---------------------------------------------------------------
check_network() {
  echo -e "\n${BOLD}▸ Réseau Docker${NC}"
  if docker network inspect redteam-tor-net >/dev/null 2>&1; then
    local driver
    driver=$(docker network inspect redteam-tor-net --format '{{.Driver}}' 2>/dev/null)
    if [ "$driver" = "bridge" ]; then
      ok "redteam-tor-net: bridge (isolation OK)"
    else
      warn "redteam-tor-net driver: $driver (attendu: bridge)"
    fi
  else
    warn "réseau redteam-tor-net non trouvé"
  fi
}

# --- 7. Lancer l’instance Desktop isolée ------------------------------------
launch_opencode() {
  echo -e "\n${BOLD}▸ Lancement${NC}"
  local launcher="$REDTEAM_DIR/start-redteam-desktop.sh"
  [ -x "$launcher" ] || fail "Launcher dédié introuvable ou non exécutable: $launcher"
  info "Délégation à l'instance Desktop isolée"
  exec "$launcher"
}

# --- verify-vpn : contrôle egress VPN complet (avant tout /engage internet) ---
verify_vpn() {
  # shellcheck source=/dev/null
  . "$REDTEAM_DIR/scripts/lib/vpn_state.sh"
  echo -e "\n${BOLD}▸ Vérification egress VPN${NC}"
  local rc=0 ip org
  # shellcheck source=/dev/null
  . "$REDTEAM_DIR/scripts/lib/vpn_state.sh"
  if rt_wg_manual_up 2>/dev/null; then
    ok "tunnel WireGuard manuel actif (wg-quick, handshake récent)"
  elif rt_vpn_up; then
    ok "tunnel VPN réel détecté (état CLI + iface tun/wg/xfrm)"
  else
    fail "pas de tunnel VPN réel — voir détail: $0 start (check VPN) ou windscribe-cli status"
    rc=1
  fi
  ip=$(rt_exit_ip); org=$(rt_exit_ip_org)
  info "IPv4 de sortie: ${ip:-injoignable} ${org:+[$org]}"
  # Proprietaire de l'IP : les IP des serveurs GRATUITS sont souvent annoncees
  # sous l'AS du datacenter (WorldStream, M247, Datacamp...) et non « Proton ».
  # Dans la bulle reseau isolee (pentest-vpn), l'isolation est structurelle :
  # wg0 est l'unique route par defaut. On prouve donc l'absence de fuite en
  # comparant l'IP de sortie a l'IP directe de l'hote.
  local bubble_ok=0 host_ip=""
  if rt_in_bubble; then
    host_ip="$(rt_bubble_host_ip)"
    if [ -n "$ip" ] && [ -n "$host_ip" ] && [ "$ip" != "$host_ip" ]; then
      bubble_ok=1
    fi
  fi
  case "$org" in
      *Windscribe*|*windscribe*) ok "sortie IPv4 appartient à Windscribe" ;;
      *Proton*|*proton*) ok "sortie IPv4 appartient à Proton" ;;
      "") [ "$rc" -eq 0 ] && warn "propriétaire de l'IP non identifiable (ipinfo.io injoignable ?)" ;;
      *)
        if [ "$bubble_ok" -eq 1 ]; then
          ok "bulle isolée : sortie ${ip} [$org] ≠ IP directe hôte (${host_ip}) — aucune fuite possible"
        else
          fail "sortie IPv4 = $org — ni Windscribe ni Proton, trafic EN CLAIR"; rc=1
        fi ;;
    esac
  if rt_ipv6_leak; then
    fail "FUITE IPv6 : $(rt_exit_ip6) sort par une iface physique (désactive IPv6 ou protection Windscribe)"
    rc=1
  else
    if [ -n "$(rt_exit_ip6)" ]; then
      ok "IPv6 de sortie hors iface physique : $(rt_exit_ip6)"
    else
      info "pas d'IPv6 publique — pas de fuite IPv6 possible"
    fi
  fi
  if rt_in_bubble; then
    # Dans la bulle, le kill-switch est structurel : wg0 est la seule route par
    # defaut, il n'existe aucune sortie en clair possible.
    ok "kill-switch structurel : la bulle n'a qu'une route par défaut (wg0)"
  else
    local ws_conf="$HOME/.config/Windscribe/windscribe_cli.conf" fw_mode
    fw_mode=$(grep -E '^FirewallMode=' "$ws_conf" 2>/dev/null | cut -d= -f2 || true)
    case "$fw_mode" in
      Always) ok "kill-switch armé en permanence (FirewallMode=Always)" ;;
      *) warn "kill-switch FirewallMode=${fw_mode:-absent} — Always recommandé : windscribe-cli firewall on" ;;
    esac
  fi
  if [ "${RT_USE_TOR:-0}" = "1" ]; then
    if rt_tor_up; then
      ok "mode Tor : proxy Tor disponible"
    else
      fail "RT_USE_TOR=1 mais aucun proxy Tor (gateway docker ou 9050)"
      rc=1
    fi
  fi
  if [ "$rc" -eq 0 ]; then
    ok "egress prêt pour cibles internet"
  else
    fail "egress NON sûr — ne pas lancer d'engagement internet"
  fi
  return "$rc"
}

# --- stop --------------------------------------------------------------------
stop_stack() {
  echo -e "\n${BOLD}▸ Arrêt de la stack RedTeam${NC}"
  (cd "$DOCKER_DIR" && docker compose down 2>/dev/null) && ok "Conteneurs arrêtés" || warn "Erreur lors de l'arrêt"
  if systemctl is-active --quiet tor 2>/dev/null; then
    systemctl stop tor 2>/dev/null && ok "Daemon Tor arrêté" || warn "Erreur arrêt Tor"
  fi
}

# --- status ------------------------------------------------------------------
show_status() {
  echo -e "\n${BOLD}▸ État de la stack RedTeam${NC}"
  echo ""
  # Docker
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | head -20 || echo "  Docker non disponible"
  echo ""
  # Tor
  if port_up 9050; then
    ok "Tor SOCKS5: 127.0.0.1:9050"
  else
    warn "Tor SOCKS5: non disponible"
  fi
  # .env
  local env_file="$REDTEAM_DIR/.env"
  if [ -f "$env_file" ]; then
    local perms
    perms=$(stat -c '%a' "$env_file" 2>/dev/null || stat -f '%Lp' "$env_file" 2>/dev/null)
    [ "$perms" = "600" ] && ok ".env: 600" || warn ".env: $perms (devrait être 600)"
  fi
  # Le launcher dédié ne modifie pas la configuration TUI daily.
  if [ -f "$HOME/.config/opencode-redteam/data/auth.json" ] || [ -L "$HOME/.config/opencode-redteam/data/auth.json" ]; then
    ok "Authentification: lien daily disponible"
  else
    warn "Authentification: lien daily absent"
  fi
}

# --- Main --------------------------------------------------------------------
main() {
  case "${1:-start}" in
    stop)
      banner
      stop_stack
      ;;
    status)
      banner
      show_status
      ;;
    verify)
      banner
      exec bash "$REDTEAM_DIR/scripts/verify-tor.sh"
      ;;
    verify-vpn)
      banner
      verify_vpn
      ;;
    start|*)
      banner
      check_prereqs
      if ! check_host_vpn; then
        fail "egress VPN invalide (IP de sortie non-Windscribe) — arrêt."
        fail "Diagnostic : $0 verify-vpn"
        exit 1
      fi
      # Cibles internet : pas de VPN réel => pas de lancement (fail-closed).
      # RT_ALLOW_DIRECT=1 force le passage en connaissance de cause (lab local).
      if command -v rt_vpn_up >/dev/null 2>&1 && ! rt_vpn_up && [ "${RT_ALLOW_DIRECT:-0}" != "1" ]; then
        fail "VPN hôte absent — refus de lancer la stack pour cibles internet."
        fail "Connecte le VPN (windscribe-cli connect), vérifie: $0 verify-vpn"
        fail "Lab local uniquement ? relance avec RT_ALLOW_DIRECT=1"
        exit 1
      fi
      if [ "${RT_USE_TOR:-0}" = "1" ]; then
        start_tor_gateway
      else
        echo -e "\n${BOLD}▸ Conteneur Tor Gateway${NC}"
        info "Tor désactivé (défaut) — sortie via VPN hôte. Opt-in: RT_USE_TOR=1"
      fi
      check_images
      check_env
      check_network
      activate_theme
      launch_opencode
      ;;
  esac
}

main "$@"
