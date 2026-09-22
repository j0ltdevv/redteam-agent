function opencode-caged --description "OpenCode avec cage réseau"
    if set -q IN_OPENCODE_CAGE
        echo "[opsec] déjà dans une cage" >&2
        return 1
    end
    set -lx IN_OPENCODE_CAGE 1
    systemd-run --user --scope --quiet \
        -p IPAddressDeny=any \
        -p IPAddressAllow=127.0.0.0/8 \
        -p IPAddressAllow=192.168.56.0/24 \
        -p IPAddressAllow=10.0.0.0/8 \
        -p IPAddressAllow=172.21.0.0/16 \
        -p IPAddressAllow=1.1.1.1 \
        -p IPAddressAllow=9.9.9.9 \
        opencode $argv
end
