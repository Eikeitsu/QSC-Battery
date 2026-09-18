#!/system/bin/sh

# 独立简介刷新进程。
# 参数：父 service.sh 的 PID。worker 不依赖父 shell 中已经 source 的函数，
# 每次启动都重新加载当前模块文件，热更新后由新 service 接管新 worker。
#
# 未插电时拉长周期，避免与主循环重复刷简介；插电仍用较短间隔。
MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
PARENT_PID="${1:-0}"
. "$MODDIR/bin/common.sh" 2>/dev/null || exit 1

WORKER_PID_FILE="$DATADIR/description_worker.pid"
WORKER_LOCK="$DATADIR/.description_worker.lock"
# 插电：2 分钟；未插电：5 分钟（与 DESC_MIN_GAP / idle 对齐，不过分迟钝）
REFRESH_PLUGGED=120
REFRESH_IDLE=300

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
	# 心跳写盘约 180s 一次，探活窗口放宽到 400s
	[ "$now" -ge "$heartbeat" ] 2>/dev/null &&
		[ "$((now - heartbeat))" -le 400 ] 2>/dev/null
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
	if type qsc_description_enabled >/dev/null 2>&1 && ! qsc_description_enabled; then
		type qsc_description_restore_static >/dev/null 2>&1 &&
			qsc_description_restore_static
		worker_state 0
		exit 0
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

worker_sleep_secs() {
	local s
	if type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
		s="$REFRESH_PLUGGED"
	else
		s="${QSC_PS_IDLE_NATIVE:-$REFRESH_IDLE}"
		case "$s" in ""|*[!0-9]*|0) s="$REFRESH_IDLE" ;; esac
		[ "$s" -lt 180 ] 2>/dev/null && s=180
		[ "$s" -gt 900 ] 2>/dev/null && s=900
	fi
	printf '%s\n' "$s"
}

# 热更新/启动后：服务未就绪时短间隔重试，避免一次失败就睡到 2–5 分钟。
# 就绪后按插电状态选长周期，省电。
while worker_parent_alive; do
	worker_refresh
	if worker_service_ready; then
		sleep "$(worker_sleep_secs)"
	else
		sleep 2
	fi
	worker_parent_alive || break
done
