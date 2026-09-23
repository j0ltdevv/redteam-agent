function opencode-caged --description "OpenCode avec cage réseau (fail-closed, VPN requis)"
    if set -q IN_OPENCODE_CAGE
        echo "[opsec] déjà dans une cage" >&2
        return 1
    end

    # --- Fail-closed : aucune interface VPN => pas de cage, pas d'OpenCode ---
    set -l vpn_up 0
    set -l vpn_addrs
    for line in (ip -br addr show)
        set -l ifname (string split -m 1 ' ' -- $line)[1]
        if string match -qr '^(proton[0-9]*|wg[0-9]+|tun[0-9]+|mullvad-wg|mullvad[0-9]*|wind[0-9]+|windscribe[0-9]*|vpn[0-9]+|wireguard[0-9]*)$' -- $ifname
            set -l vpn_up 1
            set -a vpn_addrs (string match -ar '[0-9]{1,3}(?:\.[0-9]{1,3}){3}(?:/[0-9]{1,2})?' -- $line)
        end
    end
    # Fallback nmcli : VPN géré par NM sans iface tunnel visible (ex : Windscribe Linux)
    if test $vpn_up -eq 0
        if command -v nmcli >/dev/null 2>&1
            if nmcli -t -f TYPE,DEVICE connection show --active 2>/dev/null | grep -qE '^vpn:|^wireguard:'
                set -l vpn_up 1
            end
        end
    end
    if test $vpn_up -eq 0
        echo "[opsec] fail-closed : aucun VPN actif (ni iface, ni nmcli) — cage refusée" >&2
        echo "[opsec] connecte le VPN puis relance opencode-caged" >&2
        return 1
    end

    # --- Endpoint de vérification d'IP : seule destination internet autorisée en plus du lab ---
    set -l check_addrs (getent ahostsv4 am.i.mullvad.net 2>/dev/null | string match -ar '[0-9]{1,3}(?:\.[0-9]{1,3}){3}' | sort -u)
    if test (count $check_addrs) -eq 0
        echo "[opsec] WARN : résolution de am.i.mullvad.net échouée — vérification d'IP impossible depuis la cage" >&2
    end

    # --- systemd --user ignore IPAddress* (manager non-root, sans CAP_BPF) : warn ---
    set -l mgr_pid (pgrep -u (id -u) -x systemd | head -n 1)
    if test -n "$mgr_pid"; and test (ps -o uid= -p $mgr_pid | string trim) != 0
        echo "[opsec] WARN : systemd --user n'applique PAS IPAddress* (manager non-root) — filtre réseau inerte, voir references/README-anonymat.md" >&2
    end

    set -lx IN_OPENCODE_CAGE 1
    set -l sdargs --user --scope --quiet \
        -p IPAddressDeny=any \
        -p IPAddressAllow=127.0.0.0/8 \
        -p IPAddressAllow=192.168.56.0/24 \
        -p IPAddressAllow=10.0.0.0/8 \
        -p IPAddressAllow=172.21.0.0/16
    for a in $vpn_addrs $check_addrs
        set -a sdargs "-p" "IPAddressAllow=$a"
    end
    systemd-run $sdargs opencode $argv
end
