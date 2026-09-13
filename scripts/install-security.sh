#!/usr/bin/env bash

# Installation-time security hardening. This file is sourced after preflight.sh
# so these definitions intentionally replace the less strict download helpers.

security_validate_install() {
    case "$CLASHCTL_KERNEL" in
    clash | mihomo) ;;
    *)
        _errorcat "非法内核名称：$CLASHCTL_KERNEL（仅允许 clash/mihomo）"
        return 1
        ;;
    esac

    case "$CLASHCTL_HOME" in
    '' | / | /bin | /boot | /dev | /etc | /home | /lib | /lib64 | /opt | /proc | /root | /run | /sbin | /sys | /tmp | /usr | /var)
        _errorcat "拒绝使用高风险安装路径：${CLASHCTL_HOME:-<empty>}"
        return 1
        ;;
    esac

    case "$CLASHCTL_HOME" in
    *$'\n'* | *$'\r'* | *$'\t'* | *' '* | *\'* | *\"* | *'`'* | *'$'* | *';'* | *'&'* | *'|'* | *'<'* | *'>'* | *'#'* | *'\\'*)
        _errorcat "安装路径包含不安全字符，请使用不含空白/ shell 元字符的路径：$CLASHCTL_HOME"
        return 1
        ;;
    esac

    case "${GH_PROXY:-}" in
    '') ;;
    https://*)
        _failcat '⚠️ ' "已启用第三方 GitHub 下载代理：$GH_PROXY；下载内容可信度取决于该代理。" || true
        ;;
    *)
        _errorcat "GH_PROXY 仅允许 https:// 地址；建议留空直接连接 GitHub"
        return 1
        ;;
    esac
}

_secure_dependency_url() {
    case "$1" in
    https://*) return 0 ;;
    *)
        _errorcat "拒绝非 HTTPS 依赖下载地址：$1"
        return 1
        ;;
    esac
}

download_zip() {
    (($#)) || return 0
    local url_clash url_mihomo url_yq url_subconverter
    local arch
    arch=$(uname -m)

    CLASHCTL_LATEST_VERSION_FALLBACK_WARNED=0
    case "${CLASHCTL_CHECK_LATEST_VERSION:-0}" in
    1) _okcat '🔎' "查询依赖最新版本..." ;;
    esac

    local item
    for item in "$@"; do
        case $item in
        mihomo) _resolve_version VERSION_MIHOMO MetaCubeX/mihomo || return 1 ;;
        yq) _resolve_version VERSION_YQ mikefarah/yq || return 1 ;;
        subconverter) _resolve_version VERSION_SUBCONVERTER "$SUBCONVERTER_REPO" || return 1 ;;
        esac
    done

    case "$arch" in
    x86_64)
        local flags level=v1
        flags=$(grep -m1 '^flags' /proc/cpuinfo)
        grep -qw sse4_2 <<<"$flags" && grep -qw popcnt <<<"$flags" && level=v2
        grep -qw avx2 <<<"$flags" && grep -qw fma <<<"$flags" && level=v3
        VERSION_MIHOMO=${level}-$VERSION_MIHOMO

        url_clash=https://github.com/nelvko/clash-for-linux-install/releases/download/clash/clash-linux-amd64-2023.08.17.gz
        url_mihomo=https://github.com/MetaCubeX/mihomo/releases/download/${VERSION_MIHOMO##*-}/mihomo-linux-amd64-${VERSION_MIHOMO}.gz
        url_yq=https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_amd64.tar.gz
        url_subconverter=https://github.com/${SUBCONVERTER_REPO}/releases/download/${VERSION_SUBCONVERTER}/subconverter_linux64.tar.gz
        ;;
    *86*)
        url_clash=https://github.com/nelvko/clash-for-linux-install/releases/download/clash/clash-linux-386-2023.08.17.gz
        url_mihomo=https://github.com/MetaCubeX/mihomo/releases/download/${VERSION_MIHOMO##*-}/mihomo-linux-386-${VERSION_MIHOMO}.gz
        url_yq=https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_386.tar.gz
        url_subconverter=https://github.com/${SUBCONVERTER_REPO}/releases/download/${VERSION_SUBCONVERTER}/subconverter_linux32.tar.gz
        ;;
    armv*)
        url_clash=https://github.com/nelvko/clash-for-linux-install/releases/download/clash/clash-linux-armv5-2023.08.17.gz
        url_mihomo=https://github.com/MetaCubeX/mihomo/releases/download/${VERSION_MIHOMO##*-}/mihomo-linux-armv7-${VERSION_MIHOMO}.gz
        url_yq=https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_arm.tar.gz
        url_subconverter=https://github.com/${SUBCONVERTER_REPO}/releases/download/${VERSION_SUBCONVERTER}/subconverter_armv7.tar.gz
        ;;
    aarch64)
        url_clash=https://github.com/nelvko/clash-for-linux-install/releases/download/clash/clash-linux-arm64-2023.08.17.gz
        url_mihomo=https://github.com/MetaCubeX/mihomo/releases/download/${VERSION_MIHOMO##*-}/mihomo-linux-arm64-${VERSION_MIHOMO}.gz
        url_yq=https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_arm64.tar.gz
        url_subconverter=https://github.com/${SUBCONVERTER_REPO}/releases/download/${VERSION_SUBCONVERTER}/subconverter_aarch64.tar.gz
        ;;
    *)
        _errorcat "未知的架构版本：$arch，请自行下载对应版本至 ${ZIP_BASE_DIR} 目录"
        return 1
        ;;
    esac

    local -A urls=(
        [clash]="$url_clash"
        [mihomo]="$url_mihomo"
        [yq]="$url_yq"
        [subconverter]="$url_subconverter"
    )

    local url proxy_url target tmp
    _okcat '🖥️ ' "系统架构：$arch"
    for item in "$@"; do
        url="${urls[$item]}"
        proxy_url="${GH_PROXY:+${GH_PROXY%/}/}${url}"
        _secure_dependency_url "$proxy_url" || return 1

        target="${ZIP_BASE_DIR}/$(basename "$url")"
        tmp="${target}.part.$$"
        /usr/bin/rm -f -- "$tmp"

        _okcat '⏳' "正在安全下载：${item}：$proxy_url"
        curl \
            --progress-bar \
            --show-error \
            --fail \
            --location \
            --proto '=https' \
            --proto-redir '=https' \
            --max-time "$CLASHCTL_DOWNLOAD_TIMEOUT" \
            --retry 1 \
            --output "$tmp" \
            "$proxy_url" || {
                /usr/bin/rm -f -- "$tmp"
                return 1
            }

        if ! gzip -tq "$tmp" 2>/dev/null && ! unzip -tqq "$tmp" 2>/dev/null; then
            /usr/bin/rm -f -- "$tmp"
            _errorcat "依赖压缩包校验失败：$item"
            return 1
        fi

        /bin/mv -f -- "$tmp" "$target"
    done

    load_zip >&/dev/null
}
