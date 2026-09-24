#!/usr/bin/env bash
# Verify that all containers are routing traffic through Tor.
# Run this after starting the stack with start-redteam.sh.
set -e

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}
fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

ERRORS=0

echo "============================================"
echo "  Egress Isolation Verification"
echo "============================================"
echo ""

# 1. Sortie réseau : VPN hôte (défaut) ou Tor (opt-in RT_USE_TOR=1)
if [ "${RT_USE_TOR:-0}" = "1" ]
then
    echo "  Mode sortie : Tor (RT_USE_TOR=1)"

    # 1a. Check tor-gateway container is running
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^redteam-tor-gateway$"
    then
        ok "redteam-tor-gateway container is running"
    else
        fail "redteam-tor-gateway container is NOT running"
        ERRORS=$((ERRORS + 1))
    fi

    # 1b. Check Tor is bootstrapped inside the gateway
    echo -n "  Checking Tor bootstrap... "
    if docker exec redteam-tor-gateway curl -s --socks5 "127.0.0.1:9050" "https://check.torproject.org/api/ip" 2>/dev/null | grep -q "IsTor.:true"
    then
        ok "Tor is bootstrapped and working"
    else
        fail "Tor is NOT bootstrapped inside the gateway"
        ERRORS=$((ERRORS + 1))
    fi

    # 1c. Check host Tor (should also work)
    echo -n "  Checking host Tor... "
    if curl -s --socks5-hostname "127.0.0.1:9050" "https://check.torproject.org/api/ip" 2>/dev/null | grep -q "IsTor.:true"
    then
        ok "Host Tor is working"
    else
        warn "Host Tor is not available (not critical if gateway works)"
    fi
else
    echo "  Mode sortie : VPN hôte (Windscribe) — Tor désactivé"

    echo -n "  Checking host VPN... "
    VPN_STATUS="$(windscribe-cli status 2>/dev/null || echo "")"
    if echo "$VPN_STATUS" | grep -qiE "connecte|connected" && ! echo "$VPN_STATUS" | grep -qiE "coupe|disconnected"
    then
        EGRESS_IP="$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null || echo "?")"
        ok "VPN connected — egress IP: $EGRESS_IP"
    elif [ "${RT_ALLOW_DIRECT:-0}" = "1" ]
    then
        warn "VPN disconnected but RT_ALLOW_DIRECT=1 (explicit bypass, NO isolation)"
    else
        fail "VPN disconnected — egress is NOT isolated"
        ERRORS=$((ERRORS + 1))
    fi

    echo -n "  Checking kill-switch... "
    WS_CONF="$HOME/.config/Windscribe/windscribe_cli.conf"
    FW_MODE="$(grep -E '^FirewallMode=' "$WS_CONF" 2>/dev/null | cut -d= -f2 || echo "")"
    case "$FW_MODE" in
        Always) ok "kill-switch armed permanently (FirewallMode=Always)" ;;
        Auto)   warn "kill-switch only while connected (FirewallMode=Auto)" ;;
        Off)    fail "kill-switch DISABLED (FirewallMode=Off)" ; ERRORS=$((ERRORS + 1)) ;;
        *)      warn "kill-switch state unknown (FirewallMode=${FW_MODE:-absent})" ;;
    esac

    echo "  [SKIP] Tor checks skipped (VPN mode) — RT_USE_TOR=1 to verify Tor"
fi

# 4. Check each container exits through Tor (Tor mode only)
if [ "${RT_USE_TOR:-0}" = "1" ]
then
for container in kali-redteam redteam-proxy redteam-metasploit
do
    echo -n "  Checking $container... "
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"
    then
        ip=$(docker exec "$container" curl -s --socks5 "127.0.0.1:9050" "https://check.torproject.org/api/ip" 2>/dev/null || echo "")
        if echo "$ip" | grep -q "\"IsTor\":true"
        then
            ok "$container exits through Tor"
        else
            # Try with ALL_PROXY
            ip2=$(docker exec -e "ALL_PROXY=socks5h://redteam-tor-gateway:9050" "$container" curl -s "https://check.torproject.org/api/ip" 2>/dev/null || echo "")
            if echo "$ip2" | grep -q "\"IsTor\":true"
            then
                ok "$container exits through Tor (via ALL_PROXY)"
            else
                fail "$container does NOT exit through Tor"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    else
        warn "$container is not running (skipped)"
    fi
done
fi

# 5. Check .env permissions
echo -n "  Checking .env permissions... "
if [ -f "$HOME/redteam-agent/.env" ]
then
    perms=$(stat -c "%a" "$HOME/redteam-agent/.env" 2>/dev/null || stat -f "%Lp" "$HOME/redteam-agent/.env" 2>/dev/null || echo "")
    if [ "$perms" = "600" ]
    then
        ok ".env permissions are 600"
    else
        fail ".env permissions are $perms (should be 600)"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn ".env not found"
fi

# 6. Check no_container uses --network host
echo -n "  Checking docker network... "
net=$(docker network inspect "redteam-tor-net" --format "{{.Driver}}" 2>/dev/null || echo "")
if [ "$net" = "bridge" ]
then
    ok "redteam-tor-net is a bridge network (not host)"
else
    fail "redteam-tor-net is not configured as bridge"
    ERRORS=$((ERRORS + 1))
fi

# 7. Check tor-wrap.sh is fail-closed (refuses without VPN/proxy)
echo -n "  Checking egress wrap fail-closed... "
SCRIPT_DIR=$(dirname "$0" || echo ".")
WRAP_SCRIPT="$SCRIPT_DIR/tor-wrap.sh"
STUB_DIR=$(mktemp -d 2>/dev/null || echo "")
if [ -z "$STUB_DIR" ]
then
    fail "cannot create stub dir for fail-closed check"
    ERRORS=$((ERRORS + 1))
else
    for stub in docker ss windscribe-cli
    do
        printf "#!/usr/bin/env bash\nexit 0\n" > "$STUB_DIR/$stub" || echo ""
        chmod +x "$STUB_DIR/$stub" || echo ""
    done
    if PATH="$STUB_DIR:/usr/bin:/bin" "$WRAP_SCRIPT" "true" 2>/dev/null
    then
        fail "tor-wrap.sh is fail-open (ran without VPN/proxy)"
        ERRORS=$((ERRORS + 1))
    else
        ok "tor-wrap.sh is fail-closed (refuses without VPN/proxy)"
    fi
    if PATH="$STUB_DIR:/usr/bin:/bin" RT_ALLOW_DIRECT="1" "$WRAP_SCRIPT" "true" 2>/dev/null
    then
        ok "tor-wrap.sh explicit bypass RT_ALLOW_DIRECT=1 works"
    else
        fail "tor-wrap.sh explicit bypass RT_ALLOW_DIRECT=1 broken"
        ERRORS=$((ERRORS + 1))
    fi
    rm -rf "$STUB_DIR" || echo ""
fi

# 8. Check .interactsh.env permissions if present
echo -n "  Checking .interactsh.env permissions... "
FOUND_ENV=""
for candidate in "$HOME/redteam-agent/.interactsh.env" "./.opencode/.interactsh.env" "./.interactsh.env"
do
    if [ -f "$candidate" ]
    then
        FOUND_ENV="$candidate"
    fi
done
if [ -z "$FOUND_ENV" ]
then
    ok ".interactsh.env absent (skipped)"
else
    iperms=$(stat -c "%a" "$FOUND_ENV" 2>/dev/null || stat -f "%Lp" "$FOUND_ENV" 2>/dev/null || echo "")
    if [ "$iperms" = "600" ]
    then
        ok ".interactsh.env permissions are 600 ($FOUND_ENV)"
    else
        fail ".interactsh.env permissions are $iperms (should be 600) ($FOUND_ENV)"
        ERRORS=$((ERRORS + 1))
    fi
fi

# 9. Check rate ceiling doctrine ≤10 rps (no -t/--rate/RATE_LIMIT above 10 in scripts/)
echo -n "  Checking rate ceiling ≤10 rps... "
SCRIPT_LIB_DIR="$SCRIPT_DIR/lib/container.sh"
if [ -f "$SCRIPT_LIB_DIR" ]
then
    # shellcheck source=/dev/null
    . "$SCRIPT_LIB_DIR" 2>/dev/null || true
    if verify_opsec_rate_ceiling "$SCRIPT_DIR" 2>/dev/null
    then
        ok "rate ceiling ≤10 rps respected in scripts/"
    else
        fail "rate >10 détecté dans scripts/ (doctrine ≤10 rps)"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "container.sh absent, rate ceiling check skipped"
fi

# 10. Check secrets hygiene (WARN only, never FAIL)
echo -n "  Checking secrets hygiene... "
SECRET_CONF_DIR="$HOME/.config/opencode"
SECRET_HITS=""
if [ -d "$SECRET_CONF_DIR" ]
then
    SECRET_HITS=$(grep -rE -l --exclude-dir="node_modules" --exclude-dir=".git" "[0-9a-f]{64,}" "$SECRET_CONF_DIR" 2>/dev/null || echo "")
    if [ -z "$SECRET_HITS" ]
    then
        ok "no plaintext hex64 token detected"
    else
        SECRET_COUNT=$(echo "$SECRET_HITS" | wc -l || echo "?")
        warn "secret en clair possible (${SECRET_COUNT} fichier(s), valeurs masquees, rotation + chiffrement recommandes)"
    fi
else
    ok "secrets dir absent (skipped)"
fi

# 11. Check cage systemd-run (P4) — cage inactive = WARN seul, jamais FAIL
echo -n "  Checking cage systemd-run... "
if [ "${IN_OPENCODE_CAGE:-}" = "1" ]
then
    ok "cage systemd-run active"
else
    warn "cage non active (execution hors cage, statut honnete)"
fi

echo -n "  Checking systemd-run... "
if command -v systemd-run >/dev/null 2>&1
then
    ok "systemd-run present (methode P4 disponible)"
else
    fail "systemd-run absent (methode P4 non disponible)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "============================================"
if [ $ERRORS -eq 0 ]
then
    echo -e "${GREEN}All checks passed. Egress isolation is verified.${NC}"
else
    echo -e "${RED}${ERRORS} check(s) failed. Review above.${NC}"
fi
echo "============================================"
exit $ERRORS
