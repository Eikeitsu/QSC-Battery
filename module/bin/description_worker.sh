#!/system/bin/sh

# 独立简介刷新进程（按需）。
# 有 XP：仅 enter/观看时跑，离开或息屏退出。
# 无 XP：亮屏 dumpsys 降级轮询（约 20–30s），息屏退出。
MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
PARENT_PID="${1:-0}"
. "$MODDIR/bin/common.sh" 2>/dev/null || exit 1

WORKER_PID_FILE="$DATADIR/description_worker.pid"
WORKER_LOCK="$DATADIR/.description_worker.lock"
REFRESH_VIEWING_PLUGGED=45
REFRESH_VIEWING=60
REFRESH_IDLE_CHECK=30
DUMPSYS_NET_EVERY=30

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
	local secs="${1:-3600}" left chunk step
	case "$secs" in ""|*[!0-9]*) secs=3600 ;; esac

	# 有 inotifywait 时事件唤醒（Magisk busybox 常见）；失败再退回分片 sleep
	# 占位空文件，避免 consume 后路径消失导致挂不上 inotify（仅 Android）
	if command -v inotifywait >/dev/null 2>&1 && [ -d /data/system ]; then
		_iw_paths=""
		for _f in /data/system/qsc_xp_viewer /data/system/qsc_xp_fg_edge \
			/data/system/qsc_xp_screen; do
			[ -e "$_f" ] || {
				: >"$_f" 2>/dev/null || true
				chmod 0644 "$_f" 2>/dev/null || true
			}
			[ -e "$_f" ] && _iw_paths="${_iw_paths} ${_f}"
		done
		if [ -n "$_iw_paths" ]; then
			# shellcheck disable=SC2086
			inotifywait -qq -t "$secs" \
				-e modify,attrib,close_write,create,move,delete \
				$_iw_paths \
				2>/dev/null || true
			worker_parent_alive || return 1
			return 0
		fi
	fi

	# 无 inotify：大分片睡，靠非空队列唤醒。队列不再因「过期」丢弃。
	if { type qsc_ps_screen_is_off >/dev/null 2>&1 && qsc_ps_screen_is_off; } ||
		{ type qsc_ps_desc_suppressed >/dev/null 2>&1 && qsc_ps_desc_suppressed; }; then
		chunk=90
		left=$secs
		while [ "$left" -gt 0 ] 2>/dev/null; do
			step=$chunk
			[ "$left" -lt "$step" ] 2>/dev/null && step=$left
			sleep "$step"
			left=$((left - step))
			worker_parent_alive || return 1
			if type qsc_ps_screen_is_off >/dev/null 2>&1 && qsc_ps_screen_is_off; then
				:
			elif type qsc_ps_desc_suppressed >/dev/null 2>&1 && qsc_ps_desc_suppressed; then
				:
			else
				return 0
			fi
			if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
				qsc_manager_viewer_xp_edge_pending; then
				return 0
			fi
		done
		return 0
	fi
	# 亮屏空闲 ~60s 一片；观看间隔较短时 ~20s（勿再 8s 高频醒）
	chunk=60
	[ "$secs" -le 90 ] 2>/dev/null && chunk=20
	left=$secs
	while [ "$left" -gt 0 ] 2>/dev/null; do
		step=$chunk
		[ "$left" -lt "$step" ] 2>/dev/null && step=$left
		sleep "$step"
		left=$((left - step))
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

# —— 主循环：按需 —— 有 enter/观看才刷；离开或空闲则退出进程 ——
while worker_parent_alive; do
	if [ -f "$DATADIR/hot_update_fallback_reboot" ]; then
		worker_state 125
		sleep 5
		continue
	fi

	if worker_xp_mode; then
		_entered=0
		# 启动后短等边沿（主服务刚被 enter 叫醒）；无人看则退出
		if worker_poll_viewer; then
			_entered=1
		else
			worker_wait_edges 20
			if worker_poll_viewer; then
				_entered=1
			fi
		fi
		if [ "$_entered" != "1" ]; then
			type qsc_desc_viewing_clear >/dev/null 2>&1 && qsc_desc_viewing_clear
			type qsc_description_restore_static >/dev/null 2>&1 &&
				qsc_description_restore_static
			worker_state 0
			type qsc_log >/dev/null 2>&1 &&
				qsc_log debug "简介：按需退出（无管理器前台）"
			exit 0
		fi

		type qsc_log >/dev/null 2>&1 &&
			qsc_log debug "简介：管理器前台，开始刷新"
		type qsc_desc_viewing_set >/dev/null 2>&1 && qsc_desc_viewing_set
		worker_do_refresh 1
		_view_miss=0
		_view_ticks=0
		while worker_parent_alive && worker_service_ready; do
			# 息屏：停刷并退出（亮屏靠 XP enter 再拉起）
			if type qsc_ps_screen_is_off >/dev/null 2>&1 &&
				qsc_ps_screen_is_off; then
				type qsc_desc_viewing_clear >/dev/null 2>&1 &&
					qsc_desc_viewing_clear
				type qsc_description_restore_static >/dev/null 2>&1 &&
					qsc_description_restore_static
				type qsc_log >/dev/null 2>&1 &&
					qsc_log debug "简介：息屏按需退出"
				worker_state 0
				exit 0
			fi
			if worker_xp_mode; then
				worker_wait_edges "$(worker_viewing_interval)"
				if type qsc_ps_screen_is_off >/dev/null 2>&1 &&
					qsc_ps_screen_is_off; then
					type qsc_desc_viewing_clear >/dev/null 2>&1 &&
						qsc_desc_viewing_clear
					type qsc_description_restore_static >/dev/null 2>&1 &&
						qsc_description_restore_static
					worker_state 0
					exit 0
				fi
				if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
					qsc_manager_viewer_xp_edge_pending; then
					if type qsc_manager_viewer_consume_xp_edge >/dev/null 2>&1; then
						if ! qsc_manager_viewer_consume_xp_edge; then
							type qsc_desc_viewing_clear >/dev/null 2>&1 &&
								qsc_desc_viewing_clear
							type qsc_description_restore_static >/dev/null 2>&1 &&
								qsc_description_restore_static
							type qsc_log >/dev/null 2>&1 &&
								qsc_log debug "简介：已离开管理器，按需退出"
							worker_state 0
							exit 0
						fi
						_view_miss=0
						worker_do_refresh 1
						continue
					fi
				fi
				_view_ticks=$((_view_ticks + 1))
				_still=0
				if type qsc_manager_viewer_build_list >/dev/null 2>&1 &&
					type qsc_fg_pkg_in_list >/dev/null 2>&1; then
					qsc_manager_viewer_build_list \
						"${QSC_MANAGER_VIEWER_LIST:-$DATADIR/.manager_viewer_pkgs}" \
						>/dev/null 2>&1 || true
					if qsc_fg_pkg_in_list \
						"${QSC_MANAGER_VIEWER_LIST:-$DATADIR/.manager_viewer_pkgs}"; then
						_still=1
					fi
				fi
				if [ "$_still" = "1" ]; then
					_view_miss=0
					QSC_MANAGER_VIEWER_WAS=1
					type qsc_desc_viewing_set >/dev/null 2>&1 &&
						qsc_desc_viewing_set
					worker_do_refresh 0
					if [ "$((_view_ticks % 8))" -eq 0 ] 2>/dev/null; then
						type qsc_fg_xp_health_check >/dev/null 2>&1 &&
							qsc_fg_xp_health_check >/dev/null 2>&1 || true
					fi
					continue
				fi
				_view_miss=$((_view_miss + 1))
				if [ "$_view_miss" -ge 3 ] 2>/dev/null; then
					type qsc_desc_viewing_clear >/dev/null 2>&1 &&
						qsc_desc_viewing_clear
					type qsc_description_restore_static >/dev/null 2>&1 &&
						qsc_description_restore_static
					type qsc_log >/dev/null 2>&1 &&
						qsc_log debug "简介：管理器已不在前台，按需退出"
					worker_state 0
					exit 0
				fi
				QSC_MANAGER_VIEWER_WAS=1
				worker_do_refresh 0
			else
				QSC_MANAGER_VIEWER_CACHE_AT=0
				if ! worker_poll_viewer; then
					type qsc_desc_viewing_clear >/dev/null 2>&1 &&
						qsc_desc_viewing_clear
					worker_state 0
					exit 0
				fi
				worker_do_refresh 0
				worker_wait_edges "$(worker_viewing_interval)"
			fi
		done
		type qsc_desc_viewing_clear >/dev/null 2>&1 && qsc_desc_viewing_clear
		worker_state 0
		exit 0
	fi

	# —— dumpsys 回退（无 XP）：亮屏时保持轮询，约 20–30s 发现管理器；息屏则退出 ——
	if type qsc_ps_screen_is_off >/dev/null 2>&1 && qsc_ps_screen_is_off; then
		type qsc_desc_viewing_clear >/dev/null 2>&1 && qsc_desc_viewing_clear
		type qsc_description_restore_static >/dev/null 2>&1 &&
			qsc_description_restore_static
		worker_state 0
		exit 0
	fi
	worker_tick_fallback
	worker_try_recover_xp || true
done
worker_state 0
exit 0
