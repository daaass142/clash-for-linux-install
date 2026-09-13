### BEGIN INIT INFO
# Provides: placeholder_kernel_name
# Required-Start: $network $local_fs $remote_fs
# Required-Stop: $network $local_fs $remote_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: placeholder_kernel_desc
# Description: placeholder_kernel_desc
### END INIT INFO

pidfile="placeholder_pid_path"
logfile="placeholder_log_path"
cmd="placeholder_cmd_path"
cmd_args="placeholder_cmd_args"

_owned_pid() {
    pid=$1
    case "$pid" in '' | *[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/exe" ] || return 0
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || return 1
    [ "$exe" = "$cmd" ]
}

case "$1" in
start)
    $0 status >/dev/null 2>&1 && exit 0
    "$cmd" $cmd_args >"$logfile" 2>&1 &
    echo $! >"$pidfile"
    ;;
stop)
    pid=$(cat "$pidfile" 2>/dev/null)
    if _owned_pid "$pid"; then
        kill -TERM "$pid" 2>/dev/null || true
        i=0
        while _owned_pid "$pid" && [ "$i" -lt 20 ]; do
            sleep 0.1
            i=$((i + 1))
        done
        _owned_pid "$pid" && kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f -- "$pidfile"
    ;;
restart | reload)
    $0 stop
    sleep 0.5
    $0 start
    ;;
status)
    pid=$(cat "$pidfile" 2>/dev/null)
    if _owned_pid "$pid"; then
        echo "placeholder_kernel_name is running with PID: $pid"
        exit 0
    fi
    echo "placeholder_kernel_name is not running."
    exit 1
    ;;
*)
    echo "Usage: $0 {start|stop|restart|status}"
    ;;
esac
