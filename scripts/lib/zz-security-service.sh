#!/usr/bin/env bash

# Loaded after service.sh. These definitions intentionally replace the nohup
# process-control paths that used broad pkill-by-name matching.

_service_nohup_cmdline() {
    printf '%s -d %s -f %s' "$BIN_KERNEL" "$CLASH_RESOURCES_DIR" "$CLASH_CONFIG_RUNTIME"
}

_service_nohup_pids() {
    pgrep -f -x -- "$(_service_nohup_cmdline)" 2>/dev/null
}

service_sudo_start() {
    _clashctl_safe_kernel || return 1
    _is_root && service_start && return 0
    detect_service_manager
    (
        sudo -- sh -c 'nohup "$1" -d "$2" -f "$3" </dev/null >"$4" 2>&1 &' \
            sh "$BIN_KERNEL" "$CLASH_RESOURCES_DIR" "$CLASH_CONFIG_RUNTIME" "$service_log_path"
        stty opost 2>/dev/null
    )
}

service_sudo_stop() {
    _clashctl_safe_kernel || return 1
    _is_root && service_stop && return 0

    local pids=() pid
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] && pids+=("$pid")
    done < <(_service_nohup_pids)
    [ ${#pids[@]} -eq 0 ] && return 0

    sudo -- kill -TERM "${pids[@]}" 2>/dev/null || return 1
    sleep 0.2
    local survivors=()
    for pid in "${pids[@]}"; do
        kill -0 "$pid" 2>/dev/null && survivors+=("$pid")
    done
    [ ${#survivors[@]} -eq 0 ] || sudo -- kill -KILL "${survivors[@]}" 2>/dev/null
    stty opost 2>/dev/null
}

service_stop() {
    _clashctl_safe_kernel || return 1
    detect_service_manager
    case "$service_manager" in
    systemd) systemctl stop "$CLASHCTL_KERNEL" ;;
    sysvinit) service "$CLASHCTL_KERNEL" stop ;;
    openrc) rc-service "$CLASHCTL_KERNEL" stop ;;
    runit) sv down "$CLASHCTL_KERNEL" ;;
    nohup | *)
        local pids=() pid
        while IFS= read -r pid; do
            [[ "$pid" =~ ^[0-9]+$ ]] && pids+=("$pid")
        done < <(_service_nohup_pids)
        [ ${#pids[@]} -eq 0 ] && return 0
        kill -TERM "${pids[@]}" 2>/dev/null || true
        sleep 0.2
        for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
        done
        ;;
    esac
}

service_status() {
    _clashctl_safe_kernel || return 1
    detect_service_manager
    case "$service_manager" in
    systemd) systemctl status "$CLASHCTL_KERNEL" "$@" ;;
    sysvinit) service "$CLASHCTL_KERNEL" status "$@" ;;
    openrc) rc-service "$CLASHCTL_KERNEL" status "$@" ;;
    runit) sv status "$CLASHCTL_KERNEL" "$@" ;;
    nohup | *)
        local pids=() pid
        while IFS= read -r pid; do
            [[ "$pid" =~ ^[0-9]+$ ]] && pids+=("$pid")
        done < <(_service_nohup_pids)
        [ ${#pids[@]} -gt 0 ] || return 1
        ps -fp "$(IFS=,; echo "${pids[*]}")"
        ;;
    esac
}

service_is_active() {
    _clashctl_safe_kernel || return 1
    detect_service_manager
    case "$service_manager" in
    systemd) systemctl is-active "$CLASHCTL_KERNEL" >/dev/null 2>&1 ;;
    sysvinit) service "$CLASHCTL_KERNEL" status >/dev/null 2>&1 ;;
    openrc) rc-service "$CLASHCTL_KERNEL" status >/dev/null 2>&1 ;;
    runit) sv status "$CLASHCTL_KERNEL" 2>/dev/null | grep -qs '^run' ;;
    nohup | *) _service_nohup_pids >/dev/null 2>&1 ;;
    esac
}
