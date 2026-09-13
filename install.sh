#!/usr/bin/env bash

# Installer-created secrets/configs should never become group/world readable.
umask 077

CLASHCTL_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
. "$CLASHCTL_SRC/scripts/preflight.sh"
. "$CLASHCTL_SRC/scripts/install-security.sh"

valid_env
parse_args "$@"
security_validate_install || exit 1

_okcat "安装内核：$CLASHCTL_KERNEL"
_okcat '📦' "安装路径：$CLASHCTL_HOME"

prepare_zip

install_service
install_clashctl

# Sentinel used by the uninstaller to prove the deletion target is managed by us.
printf '%s\n' 'clashctl managed directory' >"$CLASHCTL_HOME/.clashctl-managed"
chmod 600 -- "$CLASHCTL_HOME/.clashctl-managed"
chmod -R go-rwx -- "$CLASHCTL_HOME" 2>/dev/null || true
touch "$CLASH_PROFILES_LOG"
_secure_config_permissions

_merge_config
_detect_proxy_port

# Never start/expose the controller with an empty or low-entropy secret.
[ -z "$(_get_secret)" ] && clashsecret "$(_get_random_val 32)" >/dev/null
clashsecret
clashui

_valid_config "$CLASH_CONFIG_BASE" && {
    CLASHCTL_SUB_URL="file://$CLASH_CONFIG_BASE"
}
clashsub add --use "$CLASHCTL_SUB_URL"
_okcat '🎉' "请执行 source ~/.bashrc 为当前 SHELL 加载 clashctl 命令"
