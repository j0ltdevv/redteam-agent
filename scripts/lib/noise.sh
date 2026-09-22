#!/usr/bin/env bash

katana_emit_out_of_scope_regexes() {
    cat <<'EOF'
https?://[^?#]*(?:%5[cC]|\\|%22|"|%27|'|\{\{|\}\}|%7[bB]%7[bB]|%7[dD]%7[dD]|%2[aA]|\*)
https?://[^?#]+/(?:assets|cdn/assets|cdnpre/assets|cdn/i18n)/(?:[^?#]*/)?(?:images?|img|icons?|fonts?|i18n)(?:/[^?#]*)?(?:$|[?#])
https?://[^?#]+/(?:assets|cdn/assets|cdnpre/assets|cdn/i18n)/(?:[^?#]*/)?(?:assets|cdn/assets|cdnpre/assets|cdn/i18n)/(?:[^?#]*)?(?:$|[?#])
https?://[^?#]+/(?:assets|cdn/assets|cdnpre/assets)/(?:[^?#]*/)?(?:scripts/lib|[bB]un)(?:/[^?#]*)?(?:$|[?#])
https?://[^?#]+/(?:[^?#]*/)?(?:[Tt]rident|[Ee]dge)(?:/[^?#]*)?(?:$|[?#])
https?://[^?#]+/(?:[^?#]*/)?(?:build/routes|node_modules)(?:/[^?#]*)?(?:$|[?#])
https?://[^?#]+/\.well-known/[^?#]+/[0-9]{2,5}/\.well-known/[^?#]+(?:/[^?#]*)?(?:$|[?#])
https?://[^?#]+\.(?:png|jpe?g|gif|webp|bmp|ico|svg|avif|mp3|mp4|wav|ogg|pdf|zip|gz|woff2?|ttf|eot|wasm(?:\.br|\.gz)?)(?:$|[?#])
EOF
}

_katana_urlish_path() {
    local value="${1:-}"
    value="${value#*://}"
    value="/${value#*/}"
    value="${value%%\?*}"
    value="${value%%\#*}"
    [[ -n "$value" ]] || value="/"
    printf '%s\n' "$value"
}

is_katana_binary_source_ref() {
    local source_ref="${1:-}"
    local source_path
    source_path="$(_katana_urlish_path "$source_ref")"
    source_path="$(printf '%s' "$source_path" | tr '[:upper:]' '[:lower:]')"

    case "$source_path" in
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.ico|*.svg|*.avif|*.mp3|*.mp4|*.wav|*.ogg|*.pdf|*.zip|*.gz|*.woff|*.woff2|*.ttf|*.eot|*.wasm|*.wasm.br|*.wasm.gz)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_katana_internal_source_path() {
    local path="${1:-}"
    local path_lower
    path_lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"

    case "$path_lower" in
        */build/routes/*|*/node_modules/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_katana_javascript_source_ref() {
    local source_ref="${1:-}"
    local source_path
    source_path="$(_katana_urlish_path "$source_ref")"
    source_path="$(printf '%s' "$source_path" | tr '[:upper:]' '[:lower:]')"

    case "$source_path" in
        *.js|*.mjs|*.cjs|*.jsx|*.js.map|*.mjs.map|*.cjs.map|*.jsx.map)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_katana_api_like_path() {
    local path="${1:-}"
    local path_lower
    path_lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"

    case "$path_lower" in
        /api/*|/rest/*|/graphql*|/graphiql*|/priapi/*|/v[0-9]/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_katana_low_signal_realtime_url() {
    local url="${1:-}"
    local path_lower query_lower

    [[ -n "$url" ]] || return 1

    path_lower="$(_katana_urlish_path "$url")"
    path_lower="$(printf '%s' "$path_lower" | tr '[:upper:]' '[:lower:]')"
    query_lower=""
    if [[ "$url" == *\?* ]]; then
        query_lower="${url#*\?}"
        query_lower="$(printf '%s' "$query_lower" | tr '[:upper:]' '[:lower:]')"
    fi

    case "$path_lower" in
        /socket.io|/socket.io/)
            if [[ "$query_lower" == *"transport=polling"* ]]; then
                return 0
            fi
            ;;
    esac

    return 1
}

is_katana_noise_source() {
    local source_ref="${1:-}"
    local _tag="${2:-}"
    local _attribute="${3:-}"
    local _content_type="${4:-}"
    local _error_text="${5:-}"

    [[ -n "$source_ref" ]] || return 1

    if is_katana_binary_source_ref "$source_ref"; then
        return 0
    fi

    # Treat asset-directory source pages as noise too. Some SPA targets serve index.html
    # for arbitrary asset subpaths (for example /assets/.../), which makes katana emit
    # recoverable error discoveries for bogus relative .js/.css links under those paths.
    # Those rows have no trustworthy response metadata and poison the crawl queue.
    local source_path
    source_path="$(_katana_urlish_path "$source_ref")"
    if is_katana_noise_path "$source_path" || is_katana_internal_source_path "$source_path"; then
        return 0
    fi

    return 1
}

is_katana_noise_path() {
    local path="${1:-}"
    local path_lower
    path_lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"

    [[ -z "$path" ]] && return 0

    if printf '%s' "$path_lower" | grep -qiE "(%5c|\\\\|%22|\"|\{\{|\}\}|%7b%7b|%7d%7d|%2a|\*|'\+|\+'|\"\\\+|\+\")"; then
        return 0
    fi

    if printf '%s' "$path_lower" | grep -qiE "['\"]\.concat\(|/\.concat\("; then
        return 0
    fi

    case "$path_lower" in
        *'$')
            return 0
            ;;
    esac

    case "$path_lower" in
        /application/vnd.*|/text/*|/audio/*|/video/*|/image/*|/font/*)
            return 0
            ;;
    esac

    case "$path_lower" in
        /assets/*/|/cdn/assets/*/|/cdnpre/assets/*/|/cdn/i18n/*/)
            return 0
            ;;
        /assets/*/images/*|/assets/*/img/*|/assets/*/icons/*|/assets/*/fonts/*|/assets/i18n/*|*/assets/public/assets/public/*)
            return 0
            ;;
        /cdn/assets/*/images/*|/cdn/assets/*/img/*|/cdn/assets/*/icons/*|/cdn/assets/*/fonts/*|/cdnpre/assets/*/images/*|/cdnpre/assets/*/img/*|/cdnpre/assets/*/icons/*|/cdnpre/assets/*/fonts/*|/cdn/i18n/*|*/assets/i18n/assets/public/*)
            return 0
            ;;
    esac

    case "$path_lower" in
        /edge/|/trident/|/edge/*|/trident/*|/-)
            return 0
            ;;
    esac

    if printf '%s' "$path_lower" | grep -Eq '/\.well-known/[^/]+/[0-9]{2,5}/\.well-known/[^/]+'; then
        return 0
    fi

    return 1
}

# Pilier 3 furtivite — plafond effectif ≤10 req/s par defaut
# RT_MAX_RPS est borne a 10 en dur par rt_stealth_max_rps
# Chaque requete doit appeler rt_stealth_jitter_sleep avant envoi
# Le jitter aleatoire utilise $RANDOM entre 0 et RT_JITTER_MAX_MS
# Blending : HTTPS/443 privilegie, User-Agent rotatif via rt_random_user_agent
# depuis scripts/templates/user-agents.txt, metadonnees nettoyees via
# rt_strip_payload_metadata, jamais d IP reelle sans proxy via
# rt_require_proxy_or_loopback. Compatible avec scripts/lib/container.sh
# qui source deja ce fichier sans le modifier.
RT_MAX_RPS="${RT_MAX_RPS:-10}"
RT_JITTER_MAX_MS="${RT_JITTER_MAX_MS:-900}"
RT_CONNECT_TIMEOUT="${RT_CONNECT_TIMEOUT:-5}"
RT_MAX_TIME="${RT_MAX_TIME:-20}"
RT_UA_FILE_FALLBACK="${RT_UA_FILE_FALLBACK:-}"

rt_stealth_max_rps() {
    local raw="${RT_MAX_RPS:-10}"
    local capped="10"
    if [[ "$raw" =~ ^[0-9]+$ ]]
    then
        capped="$raw"
    fi
    if (( capped > 10 ))
    then
        capped="10"
    fi
    if (( capped < 1 ))
    then
        capped="1"
    fi
    printf '%s\n' "$capped"
}

rt_stealth_base_delay_secs() {
    local rps
    rps="$(rt_stealth_max_rps)"
    awk -v r="$rps" 'BEGIN { printf "%.3f", 1 / r }' || printf '%s\n' "0.100"
}

rt_stealth_jitter_sleep() {
    local max_ms="${RT_JITTER_MAX_MS:-900}"
    local base rand_ms delay_secs
    if [[ ! "$max_ms" =~ ^[0-9]+$ ]]
    then
        max_ms="900"
    fi
    base="$(rt_stealth_base_delay_secs)"
    rand_ms="$(( RANDOM % (max_ms + 1) ))"
    delay_secs="$(awk -v b="$base" -v j="$rand_ms" 'BEGIN { printf "%.3f", b + (j / 1000) }')" || return 0
    sleep "$delay_secs" || true
}

rt_random_user_agent() {
    local ua_file="${1:-${RT_UA_FILE_FALLBACK:-}}"
    local lines=()
    local line count idx
    [[ -n "$ua_file" ]] || return 1
    [[ -f "$ua_file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]
    do
        if [[ "$line" =~ ^[[:space:]]*$ ]]
        then
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*# ]]
        then
            continue
        fi
        lines+=("$line")
    done < "$ua_file" || return 1
    count="${#lines[@]}"
    if (( count == 0 ))
    then
        return 1
    fi
    idx="$(( RANDOM % count ))"
    printf '%s\n' "${lines[$idx]}"
}

rt_strip_payload_metadata() {
    local target="${1:-}"
    local stamp="${SOURCE_DATE_EPOCH:-}"
    local datestr="2020-01-01 00:00:00 UTC"
    [[ -n "$target" ]] || return 1
    [[ -e "$target" ]] || return 1
    if [[ -n "$stamp" ]]
    then
        datestr="@${stamp}"
    fi
    touch -d "$datestr" "$target" || return 1
    if command -v strip >/dev/null 2>&1
    then
        if [[ "$target" =~ \.(sh|txt|md|json|yaml|yml)$ ]]
        then
            return 0
        fi
        strip "$target" >/dev/null 2>&1 || true
    fi
    return 0
}

rt_require_proxy_or_loopback() {
    local url="${1:-}"
    local hostpart="${2:-}"
    if [[ -n "${ALL_PROXY:-}" ]] || [[ -n "${all_proxy:-}" ]]
    then
        return 0
    fi
    if [[ -n "${HTTPS_PROXY:-}" ]] || [[ -n "${https_proxy:-}" ]] || [[ -n "${HTTP_PROXY:-}" ]] || [[ -n "${http_proxy:-}" ]]
    then
        return 0
    fi
    if [[ "${RT_ALLOW_DIRECT:-0}" == "1" ]]
    then
        return 0
    fi
    if [[ "$hostpart" == "localhost" ]] || [[ "$hostpart" == "127.0.0.1" ]] || [[ "$hostpart" == "host.docker.internal" ]]
    then
        return 0
    fi
    if [[ "$url" == *"://localhost"* ]] || [[ "$url" == *"://127.0.0.1"* ]] || [[ "$url" == *"://host.docker.internal"* ]]
    then
        return 0
    fi
    echo "[stealth] refusing direct egress without proxy for ${url:-unknown target}" >&2 || true
    return 1
}
