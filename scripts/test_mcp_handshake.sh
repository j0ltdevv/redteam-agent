#!/usr/bin/env bash
# ============================================================================
#  test_mcp_handshake.sh — sonde les MCP de .opencode/opencode.json.
#
#  Pour chaque serveur : envoie initialize + notifications/initialized +
#  tools/list sur stdio et vérifie qu'on reçoit une réponse tools/list parsable.
#  C'est une sonde LOCALE : RT_ALLOW_DIRECT=1 est forcé (aucun trafic cible),
#  donc elle marche VPN connecté OU coupé. Elle ne prouve que le démarrage du
#  plugin, pas la route egress (pour ça : ./start-redteam.sh verify).
#
#  Usage:
#    ./scripts/test_mcp_handshake.sh            → tous les serveurs
#    ./scripts/test_mcp_handshake.sh nmap-mcp   → un seul
#  Env:
#    MCP_PROBE_TIMEOUT=30   timeout par serveur
# ============================================================================
set -uo pipefail

RT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT="${MCP_PROBE_TIMEOUT:-30}"
INTERACTSH_SERVER="${INTERACTSH_SERVER:-oast.pro}"
export RT_ALLOW_DIRECT=1   # sonde locale explicite (loggé par les wrappers)

probe() {
  local name="$1"; shift
  local sleep_s="$1"; shift   # délai avant EOF stdin (serveurs lents : plus long)
  local errf="/tmp/mcp-probe-${name//\//_}.err"
  local out n
  out=$(
    {
      printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"0.0"}}}' \
        '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
      sleep "$sleep_s"
    } | timeout "$TIMEOUT" "$@" 2>"$errf"
  )
  # Critère de succès : une réponse tools/list (id=2) parsable. On ne teste pas
  # serverInfo : les vieux SDK (mcp<2, ex. hexstrike) ne l'incluent pas toujours.
  n=$(printf '%s' "$out" | python3 -c '
import sys, json
tc = None
for line in sys.stdin:
    try:
        o = json.loads(line)
    except Exception:
        continue
    if o.get("id") == 2 and isinstance(o.get("result"), dict) and "tools" in o["result"]:
        tc = len(o["result"]["tools"]); break
print("" if tc is None else tc)' 2>/dev/null)
  if [ -n "$n" ]; then
    echo "OK   $name ($n tools)"
    return 0
  fi
  echo "FAIL $name — détails: $errf"
  return 1
}

run_probe() {
  case "$1" in
    metasploit)    probe metasploit 6 bash "$RT_DIR/scripts/start_metasploit_mcp.sh" ;;
    hexstrike)     probe hexstrike 25 "$HOME/.local/bin/uv" run --with "mcp<2" --with requests \
                     "$HOME/pentest-lab/hotel-lab/hexstrike-ai/hexstrike_mcp.py" --server http://127.0.0.1:8888 ;;
    interactsh)    probe interactsh 6 bash "$RT_DIR/scripts/tor-wrap.sh" "$HOME/.local/bin/interactsh-mcp" ;;
    sec-toolkit)   probe sec-toolkit 6 "$HOME/.local/bin/mcp-security-toolkit" ;;
    obscura)       probe obscura 6 bash "$RT_DIR/scripts/mcp_obscura.sh" ;;
    playwright)    probe playwright 12 bash "$RT_DIR/scripts/mcp_playwright.sh" ;;
    wstg-pentest)  probe wstg-pentest 12 "$HOME/.local/bin/uv" --directory "$HOME/pentest-lab/autopentest-ai/server" run server.py ;;
    osint)         probe osint 12 bash "$RT_DIR/scripts/egress-wrap.sh" npx -y osint-mcp-server ;;
    caido)         probe caido 6 "$HOME/go/bin/caido-mcp-server" serve --url http://127.0.0.1:7000 ;;
    nmap-mcp)      probe nmap-mcp 8 bash "$RT_DIR/scripts/egress-wrap.sh" node "$RT_DIR/.tools/nmap-mcp-server/dist/index.js" ;;
    nuclei-mcp)    probe nuclei-mcp 6 bash "$RT_DIR/scripts/tor-socks5-wrap.sh" "$RT_DIR/.tools/nuclei-mcp/nuclei-mcp" ;;
    cve-lookup)    probe cve-lookup 6 bash "$RT_DIR/scripts/egress-wrap.sh" "$HOME/.local/bin/cve-lookup-mcp" ;;
    *) echo "serveur inconnu: $1 (voir .opencode/opencode.json)" >&2; return 2 ;;
  esac
}

ALL=(metasploit hexstrike interactsh sec-toolkit obscura playwright wstg-pentest osint caido nmap-mcp nuclei-mcp cve-lookup)
SERVERS=("${@:-${ALL[@]}}")

echo "Sonde MCP (RT_ALLOW_DIRECT=1, timeout ${TIMEOUT}s) — ${#SERVERS[@]} serveur(s)"
fail=0
for s in "${SERVERS[@]}"; do
  run_probe "$s" || fail=$((fail+1))
done
echo "—"
if [ "$fail" -gt 0 ]; then
  echo "$fail serveur(s) en échec"
  exit 1
fi
echo "tous OK"
