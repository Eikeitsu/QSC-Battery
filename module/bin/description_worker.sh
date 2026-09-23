#!/system/bin/sh

# 独立简介刷新进程。
# 有 XP 且健康：空闲长睡等边沿（chunk≈15s，边沿新鲜窗 30s）；管理器会话经 XP
# 稳定后 enter，观看中温和复刷；确认离开后再经超时才 leave。
# 亮屏边沿会补发 enter（防息屏后卡住静态文案）。
# 无 XP / XP 异常：dumpsys 降级；边沿恢复后自动切回 XP。
# 注意：切勿用 1–2s 短片轮询等边沿——会把「事件驱动」打回成高频 shell 唤醒。
MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
PARENT_PID="${1:-0}"
. "$MODDIR/bin/common.sh" 2>/dev/null || exit 1

WORKER_PID_FILE="$DATADIR/description_worker.pid"
WORKER_LOCK="$DATADIR/.description_worker.lock"
REFRESH_VIEWING_PLUGGED=45
REFRESH_VIEWING=60
REFRESH_IDLE_CHECK=30
# XP 健康时空闲 dumpsys 安全网降频（每 N 次长等才扫一次，避免待机每 2 分钟 dumpsys）
DUMPSYS_NET_EVERY=5

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
	# 勿 touch 边沿文件：mtime 会被当成 pending，误消费空边沿
	if command -v inotifywait >/dev/null 2>&1; then
		_iw_paths=""
		for _f in /data/system/qsc_xp_viewer /data/system/qsc_xp_fg_edge \
			/data/system/qsc_xp_screen; do
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

	# 息屏/简介压制：不必高频探边沿，但也不能一次睡死超过边沿新鲜窗（~30s），
	# 否则亮屏后 XP 已写 enter，worker 仍在长睡 → 边沿过期 → 简介不及时。
	if { type qsc_ps_screen_is_off >/dev/null 2>&1 && qsc_ps_screen_is_off; } ||
		{ type qsc_ps_desc_suppressed >/dev/null 2>&1 && qsc_ps_desc_suppressed; }; then
		chunk=25
		left=$secs
		while [ "$left" -gt 0 ] 2>/dev/null; do
			step=$chunk
			[ "$left" -lt "$step" ] 2>/dev/null && step=$left
			sleep "$step"
			left=$((left - step))
			worker_parent_alive || return 1
			# 已亮屏且离开压制：立刻返回，让上层吃边沿 / dumpsys
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
	# 边沿新鲜窗口约 30s：空闲用 ~15s，观看间隔较短时用 ~8s
	chunk=15
	[ "$secs" -le 60 ] 2>/dev/null && chunk=8
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

# —— 主循环：XP ↔ dumpsys 可切换 ——
_was_suppressed=0
_idle_net_ticks=0
while worker_parent_alive; do
	if [ -f "$DATADIR/hot_update_fallback_reboot" ]; then
		worker_state 125
		sleep 5
		continue
	fi

	if worker_xp_mode; then
		# 空闲：长睡等边沿；健康检查；dumpsys 安全网降频（非「XP 坏了」）
		_entered=0
		while worker_parent_alive && worker_xp_mode && worker_service_ready; do
			if worker_poll_viewer; then
				_entered=1
				_was_suppressed=0
				_idle_net_ticks=0
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
				worker_wait_edges 180
				continue
			fi
			# 刚离开息屏压制：立刻 dumpsys，勿再空等一轮
			if [ "$_was_suppressed" = "1" ]; then
				_was_suppressed=0
				if worker_dumpsys_manager_hit; then
					type qsc_log >/dev/null 2>&1 &&
						qsc_log debug "简介：亮屏后 dumpsys 发现管理器"
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
			_idle_net_ticks=$((_idle_net_ticks + 1))
			# 首轮空闲超时就跑安全网；之后每 N 轮一次，避免待机频繁 dumpsys
			if [ "$_idle_net_ticks" -gt 1 ] 2>/dev/null &&
				[ "$((_idle_net_ticks % ${DUMPSYS_NET_EVERY:-5}))" -ne 0 ] 2>/dev/null; then
				continue
			fi
			if worker_dumpsys_manager_hit; then
				type qsc_log >/dev/null 2>&1 &&
					qsc_log debug "简介：dumpsys 安全网发现管理器（未读到新鲜 XP 边沿，LSP 仍可能正常）"
				QSC_MANAGER_VIEWER_WAS=1
				QSC_MANAGER_VIEWER_RISING=1
				_entered=1
				_idle_net_ticks=0
				break
			fi
		done

		if [ "$_entered" = "1" ] && worker_parent_alive && worker_service_ready; then
			type qsc_log >/dev/null 2>&1 &&
				qsc_log debug "简介：管理器前台，开始刷新"
			worker_do_refresh 1
			_view_miss=0
			_view_ticks=0
			while worker_parent_alive && worker_service_ready; do
				if worker_xp_mode; then
					worker_wait_edges "$(worker_viewing_interval)"
					if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
						qsc_manager_viewer_xp_edge_pending; then
						if type qsc_manager_viewer_consume_xp_edge >/dev/null 2>&1; then
							if ! qsc_manager_viewer_consume_xp_edge; then
								type qsc_log >/dev/null 2>&1 &&
									qsc_log debug "简介：已离开管理器，停止刷新"
								break
							fi
							# 亮屏补发 enter：强制刷一次，清掉息屏留下的静态文案
							_view_miss=0
							worker_do_refresh 1
							continue
						fi
					fi
					# 无 leave：轻量用 XP fg 确认仍在管理器，避免每轮 poll→dumpsys
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
						worker_do_refresh 0
						# 健康检查降频：观看中不必每轮抽样 dumpsys
						if [ "$((_view_ticks % 8))" -eq 0 ] 2>/dev/null; then
							type qsc_fg_xp_health_check >/dev/null 2>&1 &&
								qsc_fg_xp_health_check >/dev/null 2>&1 || true
						fi
						continue
					fi
					_view_miss=$((_view_miss + 1))
					if [ "$_view_miss" -ge 3 ] 2>/dev/null; then
						type qsc_log >/dev/null 2>&1 &&
							qsc_log debug "简介：管理器已不在前台，停止刷新"
						break
					fi
					QSC_MANAGER_VIEWER_WAS=1
					worker_do_refresh 0
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
