#!/system/bin/sh

# 独立简介刷新进程。
# 参数：父 service.sh 的 PID。worker 不依赖父 shell 中已经 source 的函数，
# 每次启动都重新加载当前模块文件，热更新后由新 service 接管新 worker。
MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
PARENT_PID="${1:-0}"
. "$MODDIR/bin/common.sh" 2>/dev/null || exit 1

WORKER_PID_FILE="$DATADIR/description_worker.pid"
WORKER_LOCK="$DATADIR/.description_worker.lock"
REFRESH_SECS="${QSC_PS_DESC_MIN_GAP:-30}"
case "$REFRESH_SECS" in
	""|*[!0-9]*) REFRESH_SECS=30 ;;
esac
[ "$REFRESH_SECS" -ge 10 ] 2>/dev/null || REFRESH_SECS=10

case "$PARENT_PID" in
	""|*[!0-9]*) PARENT_PID=0 ;;
esac

if [ -d "$WORKER_LOCK" ]; then
	_old_pid="$(cat "$WORKER_LOCK/pid" 2>/dev/null | tr -d ' \r\n')"
	case "$_old_pid" in
		""|*[!0-9]*) rm -rf "$WORKER_LOCK" 2>/dev/null ;;
		*) kill -0 "$_old_pid" 2>/dev/null || rm -rf "$WORKER_LOCK" 2>/dev/null ;;
	esac
fi
mkdir "$WORKER_LOCK" 2>/dev/null || exit 0
printf '%s\n' "$$" >"$WORKER_LOCK/pid" 2>/dev/null
printf '%s\n' "$$" >"$WORKER_PID_FILE" 2>/dev/null

worker_cleanup() {
	if [ -r "$WORKER_PID_FILE" ] &&
		[ "$(cat "$WORKER_PID_FILE" 2>/dev/null | tr -d ' \r\n')" = "$$" ]; then
		rm -f "$WORKER_PID_FILE" 2>/dev/null
	fi
	if [ -r "$WORKER_LOCK/pid" ] &&
		[ "$(cat "$WORKER_LOCK/pid" 2>/dev/null | tr -d ' \r\n')" = "$$" ]; then
		rm -rf "$WORKER_LOCK" 2>/dev/null
	fi
}
trap worker_cleanup 0 1 2 3 15

worker_parent_alive() {
	[ "$PARENT_PID" -gt 0 ] 2>/dev/null || return 1
	kill -0 "$PARENT_PID" 2>/dev/null
}

worker_service_ready() {
	local service_pid service_state heartbeat now
	service_pid="$(cat "$DATADIR/service_pid" 2>/dev/null | tr -d ' \r\n')"
	[ "$service_pid" = "$PARENT_PID" ] || return 1
	service_state="$(sed -n 's/^state=//p' "$DATADIR/service_start.state" 2>/dev/null | head -n1 | tr -d ' \r')"
	[ "$service_state" = "running" ] || return 1
	heartbeat="$(cat "$DATADIR/service_heartbeat" 2>/dev/null | tr -d ' \r\n')"
	now="$(date +%s 2>/dev/null)"
	[ -n "$heartbeat" ] && [ -n "$now" ] || return 1
	case "$heartbeat:$now" in *[!0-9:]*) return 1 ;; esac
	[ "$now" -ge "$heartbeat" ] 2>/dev/null &&
		[ "$((now - heartbeat))" -le 15 ] 2>/dev/null
}

worker_state() {
	local rc="$1" now
	now="$(date +%s 2>/dev/null)"
	case "$now" in ""|*[!0-9]*) now=0 ;; esac
	printf 'pid=%s\nparent=%s\nlast_refresh=%s\nrc=%s\n' \
		"$$" "$PARENT_PID" "$now" "$rc" \
		>"$DATADIR/description_worker.state.tmp" 2>/dev/null &&
		mv -f "$DATADIR/description_worker.state.tmp" \
			"$DATADIR/description_worker.state" 2>/dev/null
}

worker_refresh() {
	if [ -f "$DATADIR/hot_update_fallback_reboot" ]; then
		worker_state 125
		return 125
	fi
	if ! worker_service_ready; then
		worker_state 126
		return 0
	fi
	if ! type qsc_ps_load_conf >/dev/null 2>&1 ||
		! type qsc_ps_refresh_desc >/dev/null 2>&1; then
		worker_state 127
		return 127
	fi
	qsc_ps_load_conf
	qsc_ps_now
	qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
	_rc="$?"
	worker_state "$_rc"
	return "$_rc"
}

# 热更新文案写入后立即刷新一次，之后按配置周期更新。
worker_refresh
while worker_parent_alive; do
	sleep "$REFRESH_SECS"
	worker_parent_alive || break
	worker_refresh
done
