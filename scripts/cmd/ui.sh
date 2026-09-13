#!/usr/bin/env bash

clashui() {
    _detect_ext_addr
    service_is_active >&/dev/null || service_start >/dev/null
    service_is_active >&/dev/null || _errorcat "无法启动服务，请检查日志" || return

    local local_ip=$EXT_IP
    [ -z "$local_ip" ] && local_ip=127.0.0.1
    local local_address="http://${local_ip}:${EXT_PORT}/ui"

    printf "\n"
    printf "╔═══════════════════════════════════════════════╗\n"
    printf "║                %s                  ║\n" "$(_okcat 'Web 控制台')"
    printf "║═══════════════════════════════════════════════║\n"
    printf "║                                               ║\n"
    printf "║     🏠 本机：%-31s  ║\n" "$local_address"
    printf "║                                               ║\n"
    printf "╚═══════════════════════════════════════════════╝\n"
    printf "\n"

    case "$EXT_IP" in
    127.0.0.1 | ::1 | localhost)
        _okcat '🔒' '控制接口仅本机可访问；远程管理建议使用 SSH 端口转发。'
        ;;
    *)
        _failcat '⚠️ ' "控制接口当前监听非回环地址：$EXT_IP，请确认已设置强密钥并限制防火墙来源。" || true
        ;;
    esac
}
