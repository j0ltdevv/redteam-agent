#!/usr/bin/env bash
# check_egress_contract.sh — régression du contrat d'egress (VPN-first, Tor opt-in).
#
# Vérifie :
#   1. tor-wrap.sh est fail-closed sans VPN, et le bypass explicite fonctionne
#   2. egress_proxy_flags / egress_dns_flags : vides en mode VPN, remplis en mode Tor
#   3. plus aucun appel orphelin à start_host_tor dans start-redteam.sh
#   4. le kill-switch Windscribe n'est pas désactivé
#
# Usage : scripts/check_egress_contract.sh   (exit 0 = ok, 1 = échec)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
WARN=0

ok()   { PASS=$((PASS + 1)); echo "[OK]   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "[FAIL] $1"; }
warn() { WARN=$((WARN + 1)); echo "[WARN] $1"; }

# --- 1. tor-wrap.sh : fail-closed sans VPN, bypass via RT_ALLOW_DIRECT -------
STUB_DIR="$(mktemp -d)"
for stub in docker ss windscribe-cli
do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_DIR/$stub"
    chmod +x "$STUB_DIR/$stub"
done
if PATH="$STUB_DIR:/usr/bin:/bin" "$REPO_DIR/scripts/tor-wrap.sh" true >/dev/null 2>&1
then
    bad "tor-wrap.sh is fail-open (ran without VPN)"
else
    ok "tor-wrap.sh refuses to run without VPN (fail-closed)"
fi
if PATH="$STUB_DIR:/usr/bin:/bin" RT_ALLOW_DIRECT=1 "$REPO_DIR/scripts/tor-wrap.sh" true >/dev/null 2>&1
then
    ok "RT_ALLOW_DIRECT=1 explicit bypass works"
else
    bad "RT_ALLOW_DIRECT=1 bypass broken"
fi
rm -rf "$STUB_DIR"

# --- 2. helpers de flags egress ----------------------------------------------
FN_FILE="$(mktemp)"
sed -n '/^egress_proxy_flags()/,/^}/p;/^egress_dns_flags()/,/^}/p' \
    "$REPO_DIR/scripts/lib/container.sh" > "$FN_FILE"

cat > "$FN_FILE.wrap" <<'EOW'
#!/usr/bin/env bash
source "$1"
printf '%s|%s' "$(egress_proxy_flags)" "$(egress_dns_flags)"
EOW

vpn_out="$(RT_USE_TOR=0 bash "$FN_FILE.wrap" "$FN_FILE" 2>/dev/null || true)"
if [ "$vpn_out" = "|" ]
then
    ok "VPN mode injects no proxy and no --dns override"
else
    bad "VPN mode still injects egress flags: [$vpn_out]"
fi

tor_out="$(RT_USE_TOR=1 bash "$FN_FILE.wrap" "$FN_FILE" 2>/dev/null || true)"
case "$tor_out" in
    *ALL_PROXY=socks5h://redteam-tor-gateway:9050*"--dns 127.0.0.1"*)
        ok "Tor mode restores proxy env + gateway DNS" ;;
    *)
        bad "Tor mode egress flags wrong: [$tor_out]" ;;
esac
rm -f "$FN_FILE" "$FN_FILE.wrap"

# --- 3. aucun appel orphelin à la fonction Tor supprimée ---------------------
if grep -qE '^[[:space:]]*start_host_tor[[:space:]]*$' "$REPO_DIR/start-redteam.sh"
then
    bad "start-redteam.sh still calls the removed start_host_tor"
else
    ok "start-redteam.sh has no orphan start_host_tor call"
fi

# --- 4. kill-switch Windscribe (drift-aware) --------------------------------
# NOTE : windscribe_cli.conf est RÉGÉNÉRÉ par l'app depuis son état interne.
# Un FirewallMode=Always écrit à la main est écrasé au prochain démarrage de
# l'app (constaté le 2026-09-24 : le log a dit « Set firewall on boot: false »).
# Le kill switch permanent se règle DANS L'APP ; ce test ne fait que constater.
WS_CONF="$HOME/.config/Windscribe/windscribe_cli.conf"
if [ -f "$WS_CONF" ]
then
    fw_mode="$(grep -E '^FirewallMode=' "$WS_CONF" 2>/dev/null | cut -d= -f2 || true)"
    case "$fw_mode" in
        Always) ok "Windscribe kill-switch permanent (FirewallMode=Always)" ;;
        Auto)   warn "Windscribe kill-switch = Auto : armé SEULEMENT quand connecté (à passer en 'Always' DANS L'APP — le fichier est écrasé)" ;;
        *)      bad "Windscribe kill-switch disabled or unknown (FirewallMode=${fw_mode:-absent})" ;;
    esac
else
    bad "windscribe_cli.conf missing"
fi

# --- 5. egress-wrap.sh : même contrat fail-closed ---------------------------
STUB2="$(mktemp -d)"
for stub in docker ss windscribe-cli
do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB2/$stub"
    chmod +x "$STUB2/$stub"
done
printf '#!/usr/bin/env bash\necho "$@"\n' > "$STUB2/npx"
chmod +x "$STUB2/npx"

if PATH="$STUB2:/usr/bin:/bin" "$REPO_DIR/scripts/egress-wrap.sh" true >/dev/null 2>&1
then
    bad "egress-wrap.sh is fail-open (ran without VPN)"
else
    ok "egress-wrap.sh refuses to run without VPN (fail-closed)"
fi
if PATH="$STUB2:/usr/bin:/bin" RT_ALLOW_DIRECT=1 "$REPO_DIR/scripts/egress-wrap.sh" true >/dev/null 2>&1
then
    ok "egress-wrap.sh RT_ALLOW_DIRECT=1 bypass works"
else
    bad "egress-wrap.sh RT_ALLOW_DIRECT=1 bypass broken"
fi

# --- 6. wrappers MCP : proxy uniquement en mode Tor -------------------------
OBSCURA_OUT="$(OBSCURA_BIN=/bin/echo "$REPO_DIR/scripts/mcp_obscura.sh" 2>/dev/null || true)"
if [ "$OBSCURA_OUT" = "mcp" ]
then
    ok "mcp_obscura.sh uses no proxy in VPN mode"
else
    bad "mcp_obscura.sh VPN-mode args unexpected: [$OBSCURA_OUT]"
fi
if RT_USE_TOR=1 OBSCURA_BIN=/bin/echo "$REPO_DIR/scripts/mcp_obscura.sh" >/dev/null 2>&1
then
    bad "mcp_obscura.sh starts in Tor mode without a Tor proxy"
else
    ok "mcp_obscura.sh refuses Tor mode without a Tor proxy"
fi

PLAYWRIGHT_OUT="$(PATH="$STUB2:$PATH" "$REPO_DIR/scripts/mcp_playwright.sh" 2>/dev/null || true)"
if [ "$PLAYWRIGHT_OUT" = "-y @playwright/mcp" ]
then
    ok "mcp_playwright.sh uses no proxy in VPN mode"
else
    bad "mcp_playwright.sh VPN-mode args unexpected: [$PLAYWRIGHT_OUT]"
fi
if PATH="$STUB2:$PATH" RT_USE_TOR=1 "$REPO_DIR/scripts/mcp_playwright.sh" >/dev/null 2>&1
then
    bad "mcp_playwright.sh starts in Tor mode without a Tor proxy"
else
    ok "mcp_playwright.sh refuses Tor mode without a Tor proxy"
fi
rm -rf "$STUB2"

# --- 7. opencode.json : aucun proxy Tor en dur dans les commandes MCP -------
if python3 - "$REPO_DIR/.opencode/opencode.json" <<'EOPY'
import json
import re
import sys

raw = open(sys.argv[1]).read()
raw = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
cfg = json.loads(raw)
offenders = [
    name
    for name, spec in cfg.get('mcp', {}).items()
    if '9050' in json.dumps(spec.get('command', []))
]
if offenders:
    print('hardcoded proxy in: ' + ', '.join(offenders))
    sys.exit(1)
EOPY
then
    ok "opencode.json MCP commands have no hardcoded Tor proxy"
else
    bad "opencode.json still hardcodes a Tor proxy in an MCP command"
fi

# --- 8. lanceur redteam + raccourci niri ------------------------------------
if [ -x "$HOME/.local/bin/rt-term" ]
then
    ok "rt-term launcher installed and executable"
else
    bad "rt-term launcher missing or not executable"
fi
if grep -qE 'Ctrl\+Shift\+O[[:space:]]*\{[[:space:]]*spawn "rt-term"' \
    "$HOME/.config/niri/cfg/keybinds.kdl" 2>/dev/null
then
    ok "niri binds Ctrl+Shift+O to rt-term"
else
    bad "niri Ctrl+Shift+O bind missing"
fi

# --- 9. helper vpn-up.sh (montage du tunnel + contrôle d'egress) ------------
if [ -x "$REPO_DIR/scripts/vpn-up.sh" ] && bash -n "$REPO_DIR/scripts/vpn-up.sh" 2>/dev/null
then
    ok "vpn-up.sh present and syntax-valid"
else
    bad "vpn-up.sh missing or invalid"
fi

echo
echo "passed=$PASS failed=$FAIL warnings=$WARN"
[ "$FAIL" -eq 0 ]
