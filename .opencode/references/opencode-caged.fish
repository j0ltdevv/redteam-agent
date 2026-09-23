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

    # --- V4 : cage root via helper sudoers (CAP_BPF) ---
    # La cage bloque les cibles LAB uniquement (localhost + réseaux lab).
    # Tout le reste (web, CTF, LLM cloud) est AUTORISÉ → l'agent reste opérationnel.
    # La cage protège le LAB contre l'agent, pas l'inverse.
    set -l helper_ok 0
    if command -v sudo >/dev/null 2>&1; and test -x /usr/local/bin/opencode-cage-root
        if sudo -n true 2>/dev/null
            set -l helper_ok 1
        end
    end
    if test $helper_ok -eq 0
        echo "[opsec] FAIL : helper root /usr/local/bin/opencode-cage-root non configuré (sudoers manquant)" >&2
        echo "[opsec] Installe : sudo cp ~/redteam-agent/.opencode/references/opencode-cage-root /usr/local/bin/ && sudo chmod +x" >&2
        echo "[opsec] Puis : sudo cp ~/redteam-agent/.opencode/references/sudoers-opencode-cage /etc/sudoers.d/opencode-cage" >&2
        return 1
    end

    set -lx IN_OPENCODE_CAGE 1
    # Denylist = lab uniquement (tout le web/CTF/LLM autorisé)
    # Attention : 127/8 bloque aussi le localhost (LLM local si présent)
    set -l denylist 127.0.0.0/8 192.168.56.0/24 10.0.0.0/8 172.21.0.0/16
    sudo /usr/local/bin/opencode-cage-root $denylist -- opencode $argv
end
