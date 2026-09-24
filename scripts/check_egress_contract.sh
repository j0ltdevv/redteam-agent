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

ok()  { PASS=$((PASS + 1)); echo "[OK]   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "[FAIL] $1"; }

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

# --- 4. kill-switch Windscribe ----------------------------------------------
WS_CONF="$HOME/.config/Windscribe/windscribe_cli.conf"
if [ -f "$WS_CONF" ]
then
    fw_mode="$(grep -E '^FirewallMode=' "$WS_CONF" 2>/dev/null | cut -d= -f2 || true)"
    case "$fw_mode" in
        Always|Auto) ok "Windscribe kill-switch configured (FirewallMode=$fw_mode)" ;;
        *)           bad "Windscribe kill-switch disabled or unknown (FirewallMode=${fw_mode:-absent})" ;;
    esac
else
    bad "windscribe_cli.conf missing"
fi

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
