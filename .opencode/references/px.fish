function px --description "proxychains4 + config anonymat (dynamic_chain, DNS proxifié, 5s)"
    set -l conf $HOME/redteam-agent/.opencode/references/proxychains-anonymat.conf
    if set -q PROXYCHAINS_CONF
        set conf $PROXYCHAINS_CONF
    end
    if not test -r $conf
        echo "[px] config introuvable : $conf" >&2
        return 1
    end
    proxychains4 -f $conf $argv
end
