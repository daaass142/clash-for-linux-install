#!/usr/bin/env bash

# Runtime hardening loaded after common/config/convert. Service-specific
# overrides live in zz-security-service.sh so they are sourced after service.sh.

_clashctl_safe_kernel() {
    case "$CLASHCTL_KERNEL" in
    clash | mihomo) return 0 ;;
    *)
        _errorcat "拒绝操作非法内核名称：$CLASHCTL_KERNEL"
        return 1
        ;;
    esac
}

_get_random_val() {
    local length=${1:-32}
    [[ "$length" =~ ^[0-9]+$ ]] && [ "$length" -ge 16 ] || length=32
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$length"
}

_secure_config_permissions() {
    chmod 700 -- "$CLASHCTL_HOME" "$CLASH_RESOURCES_DIR" "$CLASH_PROFILES_DIR" 2>/dev/null || true
    local file
    for file in \
        "$CLASH_CONFIG_BASE" \
        "$CLASH_CONFIG_MIXIN" \
        "$CLASH_CONFIG_RUNTIME" \
        "$CLASH_CONFIG_TEMP" \
        "$CLASH_CONFIG_DEBUG" \
        "$CLASH_CONFIG_DEBUG_RAW" \
        "$CLASH_PROFILES_META" \
        "$CLASH_PROFILES_LOG" \
        "$CLASH_PROFILES_LOCK"; do
        [ -e "$file" ] && chmod 600 -- "$file" 2>/dev/null || true
    done
    [ -d "$CLASH_PROFILES_DIR" ] && find "$CLASH_PROFILES_DIR" -maxdepth 1 -type f -name '*.yaml' -exec chmod 600 -- {} + 2>/dev/null || true
}

# Preserve the original merge logic, then enforce permissions on files that can
# contain controller secrets, subscription URLs, node credentials or traffic data.
if declare -F _merge_config >/dev/null 2>&1; then
    eval "$(declare -f _merge_config | sed '1s/^_merge_config /_merge_config_unhardened /')"
    _merge_config() {
        _merge_config_unhardened "$@"
        local rc=$?
        _secure_config_permissions
        return "$rc"
    }
fi

_validate_subscription_url() {
    case "$1" in
    https://* | file://*) return 0 ;;
    http://*)
        [ "${CLASHCTL_ALLOW_INSECURE_HTTP:-0}" = 1 ] && {
            _failcat '⚠️ ' '正在使用明文 HTTP 订阅；内容可能被中间人篡改。' || true
            return 0
        }
        _errorcat "拒绝明文 HTTP 订阅。若你明确接受风险，可设置 CLASHCTL_ALLOW_INSECURE_HTTP=1"
        return 1
        ;;
    *)
        _errorcat "不支持的订阅 URL 协议：$1"
        return 1
        ;;
    esac
}

_download_raw_config() {
    local dest=$1
    local url=$2
    _validate_subscription_url "$url" || return 1

    local header hdr_opt=()
    header=$(mktemp "${CLASH_RESOURCES_DIR}/.header.XXXXXX" 2>/dev/null) && hdr_opt=(--dump-header "$header")

    local proto='=https,file' proto_redir='=https'
    if [ "${CLASHCTL_ALLOW_INSECURE_HTTP:-0}" = 1 ]; then
        proto='=https,http,file'
        proto_redir='=https,http'
    fi

    curl \
        --silent \
        --show-error \
        --fail \
        --location \
        --proto "$proto" \
        --proto-redir "$proto_redir" \
        --connect-timeout "${CLASHCTL_SUB_CONNECT_TIMEOUT:-5}" \
        --max-time "${CLASHCTL_SUB_TIMEOUT:-20}" \
        --retry "${CLASHCTL_SUB_RETRY:-2}" \
        --retry-delay 1 \
        --retry-connrefused \
        --user-agent "$CLASHCTL_SUB_UA" \
        "${hdr_opt[@]}" \
        --output "$dest" \
        "$url"
    local rc=$?

    if [ "$rc" -eq 0 ] && [ -f "$dest" ]; then
        local size max_bytes=${CLASHCTL_SUB_MAX_BYTES:-20971520}
        size=$(wc -c <"$dest" 2>/dev/null || printf '0')
        if [[ "$max_bytes" =~ ^[0-9]+$ ]] && [ "$max_bytes" -gt 0 ] && [ "${size:-0}" -gt "$max_bytes" ]; then
            /usr/bin/rm -f -- "$dest"
            _errorcat "订阅响应过大：${size} bytes（上限 ${max_bytes} bytes）"
            rc=1
        fi
    fi

    [ -n "$header" ] && {
        [ "$rc" -eq 0 ] && {
            FETCH_USERINFO=$(_header_value "$header" 'subscription-userinfo')
            FETCH_FILENAME=$(_attachment_filename "$header")
        }
        /usr/bin/rm -f -- "$header"
    }

    [ -e "$dest" ] && chmod 600 -- "$dest" 2>/dev/null || true
    return "$rc"
}
