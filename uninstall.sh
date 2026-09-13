#!/usr/bin/env bash

CLASHCTL_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Support both repository-side uninstall and the installed copy. Avoid sourcing
# preflight.sh here: uninstall should not need download/install helpers.
if [ -f "$CLASHCTL_SRC/.clashctl-managed" ]; then
    CLASHCTL_HOME="$CLASHCTL_SRC"
    . "$CLASHCTL_SRC/.env"
else
    . "$CLASHCTL_SRC/.env"
    . "$CLASHCTL_SRC/.env.install"
fi

for lib_file in "$CLASHCTL_SRC"/scripts/lib/*.sh; do
    [ -f "$lib_file" ] || continue
    . "$lib_file"
done
. "$CLASHCTL_SRC/scripts/cmd/off.sh"

_validate_uninstall_target() {
    local resolved
    [ -n "${CLASHCTL_HOME:-}" ] || {
        _errorcat "拒绝卸载：CLASHCTL_HOME 为空"
        return 1
    }
    case "$CLASHCTL_HOME" in
    /*) ;;
    *)
        _errorcat "拒绝卸载非绝对路径：$CLASHCTL_HOME"
        return 1
        ;;
    esac

    resolved=$(readlink -f -- "$CLASHCTL_HOME" 2>/dev/null || printf '%s' "$CLASHCTL_HOME")
    case "$resolved" in
    / | /bin | /boot | /dev | /etc | /home | /lib | /lib64 | /opt | /proc | /root | /run | /sbin | /sys | /tmp | /usr | /var)
        _errorcat "拒绝删除高风险路径：$resolved"
        return 1
        ;;
    esac

    [ -f "$CLASHCTL_HOME/.clashctl-managed" ] && return 0

    # Backward-compatible guard for installations created before the sentinel.
    if [ -f "$CLASHCTL_HOME/.env" ] && [ -d "$CLASHCTL_HOME/scripts/cmd" ] && [ -d "$CLASHCTL_HOME/resources" ]; then
        _failcat '⚠️ ' "未找到安全标记，但目录结构符合旧版 clashctl：$CLASHCTL_HOME" || true
        return 0
    fi

    _errorcat "拒绝递归删除：目标目录无法确认是 clashctl 安装目录：$CLASHCTL_HOME"
    return 1
}

_revoke_rc_safe() {
    detect_rc
    local rc tmp
    local export_line="export CLASHCTL_HOME=$CLASHCTL_HOME"
    local source_line='. $CLASHCTL_HOME/scripts/cmd/clashctl.sh'

    for rc in "$SHELL_RC_BASH" "$SHELL_RC_ZSH"; do
        [ -f "$rc" ] || continue
        tmp=$(mktemp "${rc}.clashctl.XXXXXX") || {
            _failcat "无法安全更新 shell 配置：$rc" || true
            continue
        }
        awk -v export_line="$export_line" -v source_line="$source_line" '
            $0 == "# >>> clashctl >>>" { managed=1; next }
            managed && $0 == "# <<< clashctl <<<" { managed=0; next }
            managed { next }
            $0 == export_line { next }
            $0 == source_line { next }
            { print }
        ' "$rc" >"$tmp" && cat "$tmp" >"$rc"
        /usr/bin/rm -f -- "$tmp"
    done

    if [ -n "$SHELL_RC_FISH" ] && [ -f "$SHELL_RC_FISH" ]; then
        if grep -qF '# clashctl shell-rc (managed by install.sh, do not edit)' "$SHELL_RC_FISH"; then
            /usr/bin/rm -f -- "$SHELL_RC_FISH"
        else
            _failcat '⚠️ ' "未删除非托管 fish 配置：$SHELL_RC_FISH" || true
        fi
    fi
}

_clashctl_safe_kernel >/dev/null 2>&1 || exit 1
_validate_uninstall_target || exit 1

! _is_root && tunstatus >&/dev/null && {
    _errorcat "请先关闭 Tun 模式"
    exit 1
}
uninstall_service || exit 1

# 清理旧版 sub update --auto 遗留的自管 crontab。只有成功读取现有
# crontab 后才写回，避免 `crontab -l` 失败时意外清空整个用户 crontab。
if command -v crontab >/dev/null 2>&1; then
    current_crontab=$(crontab -l 2>/dev/null) && {
        filtered_crontab=$(printf '%s\n' "$current_crontab" | grep -Fv "$CLASHCTL_CRON_TAG" || true)
        if [ "$filtered_crontab" != "$current_crontab" ]; then
            printf '%s\n' "$filtered_crontab" | crontab - || {
                _failcat '⚠️ ' '清理旧版 clashctl crontab 失败，已保留其余卸载流程。' || true
            }
        fi
    }
fi

_revoke_rc_safe
/usr/bin/rm -rf -- "$CLASHCTL_HOME"

_okcat '✨' "已卸载，相关配置已清除"
[ -n "$http_proxy" ] && _failcat '❗' "当前终端仍残留代理环境变量，重开终端即可清除"
