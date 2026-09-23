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

# --- 1. Daemon Tor hôte ------------------------------------------------------
start_host_tor() {
  echo -e "\n${BOLD}▸ Daemon Tor (hôte)${NC}"
  if ss -tln 2>/dev/null | grep -q ":9050 "; then
    ok "Tor déjà en écoute sur 127.0.0.1:9050"
  else
    info "Démarrage de tor..."
    if systemctl start tor 2>/dev/null; then
      ok "tor démarré via systemctl"
    elif command -v tor >/dev/null 2>&1; then
      nohup tor >/dev/null 2>&1 &
      sleep 3
      if port_up 9050; then
        ok "tor démarré en arrière-plan"
      else
        warn "tor ne répond pas sur :9050 — continuons quand même"
      fi
    else
      warn "tor non installé sur l'hôte (le conteneur Tor gateway fait le travail)"
    fi
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
    start|*)
      banner
      check_prereqs
      start_host_tor
      start_tor_gateway
      check_images
      check_env
      check_network
      activate_theme
      launch_opencode
      ;;
  esac
}

main "$@"
