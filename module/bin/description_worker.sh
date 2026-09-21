#!/system/bin/sh

# 独立简介刷新进程。
# 有 XP 且健康：后台零轮询；管理器会话经 XP 3s 稳定后 enter，观看中温和复刷；
# 确认离开后再经 90s 超时才 leave。亮屏边沿会补发 enter（防息屏后卡住静态文案）。
# 无 XP / XP 异常：dumpsys 降级；边沿恢复后自动切回 XP。
MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
PARENT_PID="${1:-0}"
. "$MODDIR/bin/common.sh" 2>/dev/null || exit 1

WORKER_PID_FILE="$DATADIR/description_worker.pid"
WORKER_LOCK="$DATADIR/.description_worker.lock"
REFRESH_VIEWING_PLUGGED=45
REFRESH_VIEWING=60
REFRESH_IDLE_CHECK=20

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
		[ "$((now - heartbeat))" -le 400 ] 2>/dev/null
}

worker_state() {
	local rc="$1" now
	now="$(date +%s 2>/dev/null)"
	case "$now" in ""|*[!0-9]*) now=0 ;; esac
	printf 'pid=%s\nparent=%s\nlast_refresh=%s\nrc=%s\nviewer=%s\n' \
		"$$" "$PARENT_PID" "$now" "$rc" "${QSC_MANAGER_VIEWER_WAS:-0}" \
		>"$DATADIR/description_worker.state.tmp" 2>/dev/null &&
		mv -f "$DATADIR/description_worker.state.tmp" \
			"$DATADIR/description_worker.state" 2>/dev/null
}

worker_xp_mode() {
	type qsc_fg_xp_ready >/dev/null 2>&1 && qsc_fg_xp_ready
}

worker_poll_viewer() {
	QSC_MANAGER_VIEWER_CACHE_AT=0
	type qsc_manager_viewer_poll >/dev/null 2>&1 || return 1
	qsc_manager_viewer_poll
}

worker_do_refresh() {
	local force="${1:-0}"
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
		return 1
	fi
	if ! type qsc_ps_load_conf >/dev/null 2>&1 ||
		! type qsc_ps_refresh_desc >/dev/null 2>&1; then
		worker_state 127
		return 127
	fi
	qsc_ps_load_conf
	qsc_ps_now
	type qsc_ps_policy_refresh >/dev/null 2>&1 && qsc_ps_policy_refresh
	if [ "$force" = "1" ]; then
		QSC_PS_DESC_FORCE=1
		QSC_PS_DESC_MIN_GAP=30
	elif [ "${QSC_MANAGER_VIEWER_WAS:-0}" = "1" ]; then
		QSC_PS_DESC_MIN_GAP=45
	fi
	qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
	_rc="$?"
	QSC_PS_DESC_FORCE=0
	worker_state "$_rc"
	return "$_rc"
}

worker_wait_edges() {
	local secs="${1:-3600}" left chunk=2
	case "$secs" in ""|*[!0-9]*) secs=3600 ;; esac
	left=$secs
	while [ "$left" -gt 0 ] 2>/dev/null; do
		chunk=2
		[ "$left" -lt "$chunk" ] 2>/dev/null && chunk=$left
		sleep "$chunk"
		left=$((left - chunk))
		if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
			qsc_manager_viewer_xp_edge_pending; then
			return 0
		fi
		if type qsc_fg_xp_edge_pending >/dev/null 2>&1 &&
			qsc_fg_xp_edge_pending; then
			type qsc_fg_xp_consume_edge >/dev/null 2>&1 &&
				qsc_fg_xp_consume_edge
			return 0
		fi
		worker_parent_alive || return 1
	done
	return 0
}

worker_viewing_interval() {
	if type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
		printf '%s\n' "$REFRESH_VIEWING_PLUGGED"
	else
		printf '%s\n' "$REFRESH_VIEWING"
	fi
}

worker_try_recover_xp() {
	type qsc_fg_xp_injected >/dev/null 2>&1 || return 1
	qsc_fg_xp_injected || return 1
	if type qsc_fg_xp_edge_pending >/dev/null 2>&1 && qsc_fg_xp_edge_pending 30; then
		type qsc_fg_clear_unreliable >/dev/null 2>&1 && qsc_fg_clear_unreliable
		return 0
	fi
	if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
		qsc_manager_viewer_xp_edge_pending; then
		type qsc_fg_clear_unreliable >/dev/null 2>&1 && qsc_fg_clear_unreliable
		return 0
	fi
	return 1
}

# dumpsys 安全网：XP 漏边沿时仍能发现管理器（息屏/驻停压制时禁用，避免栈里残留包名误报）
worker_dumpsys_manager_hit() {
	local list _p
	type qsc_ps_screen_is_off >/dev/null 2>&1 && qsc_ps_screen_is_off && return 1
	type qsc_ps_desc_suppressed >/dev/null 2>&1 && qsc_ps_desc_suppressed && return 1
	type qsc_manager_viewer_build_list >/dev/null 2>&1 || return 1
	type qsc_fg_dumpsys_read >/dev/null 2>&1 || return 1
	list="${QSC_MANAGER_VIEWER_LIST:-$DATADIR/.manager_viewer_pkgs}"
	qsc_manager_viewer_build_list "$list" >/dev/null 2>&1 || true
	QSC_FG_CACHE_AT=0
	QSC_FG_CACHE_PKG=""
	qsc_fg_dumpsys_read || return 1
	while IFS= read -r _p || [ -n "$_p" ]; do
		_p="$(printf '%s' "$_p" | tr -d ' \r\n')"
		[ -n "$_p" ] || continue
		[ "$_p" = "$QSC_FG_PKG" ] && return 0
	done <"$list"
	return 1
}

worker_should_refresh_fallback() {
	if ! type qsc_manager_viewer_poll >/dev/null 2>&1; then
		return 0
	fi
	QSC_MANAGER_VIEWER_CACHE_AT=0
	if qsc_manager_viewer_poll; then
		QSC_PS_DESC_FORCE=1
		return 0
	fi
	if type qsc_ps_desc_suppressed >/dev/null 2>&1 && qsc_ps_desc_suppressed; then
		return 0
	fi
	return 1
}

worker_tick_fallback() {
	if type qsc_description_enabled >/dev/null 2>&1 && ! qsc_description_enabled; then
		type qsc_description_restore_static >/dev/null 2>&1 &&
			qsc_description_restore_static
		worker_state 0
		exit 0
	fi
	if ! worker_service_ready; then
		worker_state 126
		sleep 2
		return 1
	fi
	qsc_ps_load_conf
	qsc_ps_now
	type qsc_ps_policy_refresh >/dev/null 2>&1 && qsc_ps_policy_refresh
	if worker_should_refresh_fallback; then
		[ "${QSC_MANAGER_VIEWER_WAS:-0}" = "1" ] && QSC_PS_DESC_MIN_GAP=30
		qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
		QSC_PS_DESC_FORCE=0
		worker_state "$?"
	else
		worker_state 0
	fi
	if [ "${QSC_MANAGER_VIEWER_WAS:-0}" = "1" ]; then
		worker_wait_edges "$(worker_viewing_interval)"
	else
		worker_wait_edges "$REFRESH_IDLE_CHECK"
	fi
	return 0
}

# —— 主循环：XP ↔ dumpsys 可切换 ——
_was_suppressed=0
while worker_parent_alive; do
	if [ -f "$DATADIR/hot_update_fallback_reboot" ]; then
		worker_state 125
		sleep 5
		continue
	fi

	if worker_xp_mode; then
		# 空闲：只等边沿；周期性健康检查 + dumpsys 安全网
		_entered=0
		while worker_parent_alive && worker_xp_mode && worker_service_ready; do
			if worker_poll_viewer; then
				_entered=1
				_was_suppressed=0
				break
			fi
			qsc_ps_load_conf 2>/dev/null
			qsc_ps_now 2>/dev/null
			type qsc_ps_policy_refresh >/dev/null 2>&1 && qsc_ps_policy_refresh
			if type qsc_ps_desc_suppressed >/dev/null 2>&1 && qsc_ps_desc_suppressed; then
				type qsc_description_restore_static >/dev/null 2>&1 &&
					qsc_description_restore_static
				worker_state 0
				_was_suppressed=1
				worker_wait_edges 120
				continue
			fi
			# 刚离开息屏压制：立刻 dumpsys，勿再空等一轮 120s
			if [ "$_was_suppressed" = "1" ]; then
				_was_suppressed=0
				if worker_dumpsys_manager_hit; then
					type qsc_log >/dev/null 2>&1 &&
						qsc_log info "简介：亮屏后 dumpsys 发现管理器"
					QSC_MANAGER_VIEWER_WAS=1
					QSC_MANAGER_VIEWER_RISING=1
					_entered=1
					break
				fi
			fi
			worker_state 0
			worker_wait_edges 120
			if type qsc_fg_xp_health_check >/dev/null 2>&1 &&
				! qsc_fg_xp_health_check; then
				break
			fi
			if worker_dumpsys_manager_hit; then
				type qsc_log >/dev/null 2>&1 &&
					qsc_log info "简介：dumpsys 发现管理器（XP边沿缺失，安全网）"
				QSC_MANAGER_VIEWER_WAS=1
				QSC_MANAGER_VIEWER_RISING=1
				_entered=1
				break
			fi
		done

		if [ "$_entered" = "1" ] && worker_parent_alive && worker_service_ready; then
			type qsc_log >/dev/null 2>&1 &&
				qsc_log info "简介：管理器前台，开始刷新"
			worker_do_refresh 1
			while worker_parent_alive && worker_service_ready; do
				if worker_xp_mode; then
					worker_wait_edges "$(worker_viewing_interval)"
					if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
						qsc_manager_viewer_xp_edge_pending; then
						if type qsc_manager_viewer_consume_xp_edge >/dev/null 2>&1; then
							if ! qsc_manager_viewer_consume_xp_edge; then
								type qsc_log >/dev/null 2>&1 &&
									qsc_log info "简介：已离开管理器，停止刷新"
								break
							fi
							# 亮屏补发 enter：强制刷一次，清掉息屏留下的静态文案
							worker_do_refresh 1
							continue
						fi
					fi
					# 每轮复核是否仍在看（息屏后 desc-only 无 fg 文件时勿空转写静态）
					QSC_MANAGER_VIEWER_CACHE_AT=0
					if ! worker_poll_viewer; then
						type qsc_log >/dev/null 2>&1 &&
							qsc_log info "简介：管理器已不在前台，停止刷新"
						break
					fi
					QSC_MANAGER_VIEWER_WAS=1
					worker_do_refresh 0
					type qsc_fg_xp_health_check >/dev/null 2>&1 &&
						qsc_fg_xp_health_check >/dev/null 2>&1 || true
				else
					# 观看中 XP 变坏：dumpsys 维持直到离开
					QSC_MANAGER_VIEWER_CACHE_AT=0
					worker_poll_viewer || break
					worker_do_refresh 0
					worker_wait_edges "$(worker_viewing_interval)"
				fi
			done
			continue
		fi

		# 未进入观看且可能已不可靠 → 下面走 fallback 分支
		if worker_xp_mode; then
			continue
		fi
	fi

	# —— dumpsys 回退（无 XP / 软关 / 标记不可靠）——
	worker_tick_fallback
	worker_try_recover_xp || true
done
