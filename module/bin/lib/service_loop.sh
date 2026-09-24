#!/system/bin/sh
# service: one loop iteration (defined as function so `return` replaces sourced `continue`)

# XP 路径：主服务消费边沿 + 刷简介；停掉遗留 worker。
# 无 XP：按需启停 dumpsys 降级 worker。
qsc_service_desc_ondemand_sync() {
	local _rising=0 _viewing=0 _xp=0 _rc
	type qsc_ps_policy_refresh >/dev/null 2>&1 && qsc_ps_policy_refresh

	if type qsc_fg_xp_ready >/dev/null 2>&1 && qsc_fg_xp_ready; then
		_xp=1
	fi

	# XP enter/leave 待消费：主服务先吃边沿
	if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
		qsc_manager_viewer_xp_edge_pending; then
		QSC_PS_SCREEN_CACHE_AT=0
		type qsc_ps_now >/dev/null 2>&1 && qsc_ps_now
		if type qsc_manager_viewer_consume_xp_edge >/dev/null 2>&1; then
			if qsc_manager_viewer_consume_xp_edge; then
				_rising=1
			fi
		fi
	fi

	if type qsc_desc_viewing_active >/dev/null 2>&1 &&
		qsc_desc_viewing_active; then
		_viewing=1
	fi

	# 息屏清观看：有 XP 时只信 XP 的 screen=off；无 XP 才用 Magisk 息屏探测
	if [ "$_viewing" = "1" ]; then
		_clear_view=0
		if [ "$_xp" = "1" ]; then
			if [ -f /data/system/qsc_xp_screen ] &&
				[ -f /data/system/qsc_xp_want_screen ]; then
				_mt="$(stat -c %Y /data/system/qsc_xp_screen 2>/dev/null || echo 0)"
				_nows="$(date +%s 2>/dev/null || echo 0)"
				_st="$(awk -F'\t' 'NF{print $NF; exit}' /data/system/qsc_xp_screen 2>/dev/null | tr -d ' \r\n')"
				if [ "$_st" = "off" ] &&
					[ "$_mt" -gt 0 ] 2>/dev/null &&
					[ "$((_nows - _mt))" -ge 0 ] 2>/dev/null &&
					[ "$((_nows - _mt))" -le 8 ] 2>/dev/null; then
					_clear_view=1
				fi
			fi
		elif type qsc_ps_screen_is_off >/dev/null 2>&1 &&
			qsc_ps_screen_is_off; then
			_clear_view=1
		fi
		if [ "$_clear_view" = "1" ]; then
			type qsc_desc_viewing_clear >/dev/null 2>&1 && qsc_desc_viewing_clear
			_viewing=0
			_rising=0
		fi
	fi

	if [ "$_xp" = "1" ]; then
		# 有 XP：绝不跑第二进程
		type qsc_stop_description_worker >/dev/null 2>&1 &&
			qsc_stop_description_worker
		if [ "$_viewing" = "1" ] &&
			type qsc_ps_refresh_desc >/dev/null 2>&1; then
			type qsc_ps_now >/dev/null 2>&1 && qsc_ps_now
			if [ "$_rising" = "1" ]; then
				QSC_PS_DESC_FORCE=1
				QSC_PS_DESC_MIN_GAP=15
				# 进管理器必须重写：清指纹，避免卡在 restore_static 后的静态文案
				QSC_PS_DESC_SIG=""
				QSC_PS_DESC_STATE_SIG=""
				QSC_PS_DESC_TS=0
			else
				QSC_PS_DESC_MIN_GAP=45
			fi
			qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
			_rc="$?"
			QSC_PS_DESC_FORCE=0
			if [ "$_rising" = "1" ] && [ "$_rc" -eq 0 ] 2>/dev/null; then
				type qsc_dbg >/dev/null 2>&1 &&
					qsc_dbg "简介：管理器前台，已更新电量/温度"
			elif [ "$_rising" = "1" ]; then
				type qsc_dbg >/dev/null 2>&1 &&
					qsc_dbg "简介：管理器前台，刷新失败 rc=${_rc}"
			fi
		fi
		return 0
	fi

	# 无 XP：dumpsys 降级 worker
	_desc_want=0
	if type qsc_ps_desc_worker_wanted >/dev/null 2>&1; then
		qsc_ps_desc_worker_wanted && _desc_want=1
	fi
	if [ "$_desc_want" = "1" ]; then
		type qsc_start_description_worker >/dev/null 2>&1 &&
			qsc_start_description_worker
	else
		type qsc_stop_description_worker >/dev/null 2>&1 &&
			qsc_stop_description_worker
	fi
}

qsc_service_unplug_housekeep() {
	local do_flush="${1:-0}"
	qsc_ps_now
	_now="$QSC_PS_NOW"
	qsc_service_heartbeat
	# 未插电绝不持停充锁（挡 Doze）；残留标记一并清掉
	if type qsc_ps_plugged >/dev/null 2>&1 && ! qsc_ps_plugged; then
		type qsc_stop_wakelock_release >/dev/null 2>&1 &&
			qsc_stop_wakelock_release
	fi
	if type qsc_xp_sync_fg_policy >/dev/null 2>&1; then
		_xp_plugged=0
		type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged && _xp_plugged=1
		_xp_prev="$(cat "$DATADIR/.xp_fg_plugged" 2>/dev/null | tr -d ' \r\n')"
		if [ "$_xp_plugged" != "$_xp_prev" ]; then
			printf '%s\n' "$_xp_plugged" >"$DATADIR/.xp_fg_plugged" 2>/dev/null
			qsc_xp_sync_fg_policy >/dev/null 2>&1 || true
		fi
	fi
	if type qsc_description_enabled >/dev/null 2>&1; then
		qsc_service_desc_ondemand_sync
	fi
	# XP 观看中已在 ondemand 刷过；此处仅补无人看时的状态变化简介
	if type qsc_ps_refresh_desc >/dev/null 2>&1; then
		if ! type qsc_desc_viewing_active >/dev/null 2>&1 ||
			! qsc_desc_viewing_active; then
			qsc_ps_refresh_desc "$_now"
		fi
	fi
	if [ "$do_flush" = "1" ] &&
		type qsc_history_flush_pending >/dev/null 2>&1; then
		qsc_history_flush_pending
	fi
}

qsc_service_loop_once() {
	QSC_SERVICE_LOOP_COUNT=$((QSC_SERVICE_LOOP_COUNT + 1))
	qsc_hot_finalize_maybe
	# 省电快路径：未插电且未维持停充时，本轮只读几个 online 节点就睡，
	# 不 fork qsc_switch.sh（那会重新解析约 90KB 脚本并触发多次写盘）。
	if type qsc_ps_load_conf >/dev/null 2>&1; then
		# —— 未插电 lean 再入：几乎只 wait；配置未变则跳过简介/XP 管家 ——
		if [ "${QSC_SERVICE_LEAN_IDLE:-0}" = "1" ] &&
			[ ! -f "$DATADIR/power_switch" ] &&
			[ ! -f "$MODULE_OFF_FLAG" ] &&
			type qsc_ps_plugged >/dev/null 2>&1 &&
			! qsc_ps_plugged; then
			qsc_ps_load_conf
			qsc_ps_now
			_now="$QSC_PS_NOW"
			# region agent log
			qsc_runtime_trace "H1" "loop_lean" "$QSC_SERVICE_LOOP_COUNT:$_now:${QSC_PS_CONF_RELOADED:-0}"
			# endregion
			qsc_service_heartbeat
			# 未插电强制放锁，避免残留 wake_lock 挡系统 Doze
			type qsc_stop_wakelock_release >/dev/null 2>&1 &&
				qsc_stop_wakelock_release
			# 配置变了才重做简介/XP；策略+idle 每轮都要（进深睡靠它）
			if [ "${QSC_PS_CONF_RELOADED:-0}" = "1" ]; then
				qsc_service_unplug_housekeep 0
			else
				# lean：XP 边沿/观看由主服务刷简介；无 XP 则启停降级 worker
				qsc_service_desc_ondemand_sync
			fi
			if type qsc_ps_idle_secs >/dev/null 2>&1; then
				qsc_ps_idle_secs
			else
				QSC_PS_IDLE_EFF="${QSC_PS_IDLE:-30}"
			fi
			QSC_SERVICE_SKIP_ROUNDS=$((${QSC_SERVICE_SKIP_ROUNDS:-0} + 1))
			qsc_ps_wait "${QSC_PS_IDLE_EFF:-30}"
			# region agent log
			_wait_rc="$?"
			qsc_runtime_trace "H1" "wait_exit" "$_wait_rc"
			# endregion
			# 等待返回：刷新时钟/息屏缓存，再立刻按需拉起（XP enter 可能刚打断）
			QSC_PS_SCREEN_CACHE_AT=0
			type qsc_ps_now >/dev/null 2>&1 && qsc_ps_now
			if type qsc_service_desc_ondemand_sync >/dev/null 2>&1; then
				qsc_service_desc_ondemand_sync
			fi
			return 0
		fi

		qsc_ps_load_conf
		qsc_ps_now
		_now="$QSC_PS_NOW"
		# region agent log
		qsc_runtime_trace "H1" "loop_enter" "$QSC_SERVICE_LOOP_COUNT:$_now"
		# endregion
		qsc_service_unplug_housekeep 0
		# region agent log
		qsc_runtime_trace "H1" "after_description" "$QSC_SERVICE_LOOP_COUNT"
		# endregion
		# 拔电后立即落盘未满批次的充电采样（仅从插电/满轮退出 lean 时）
		# region agent log
		qsc_runtime_trace "H5" "flush_check" "$QSC_SERVICE_LOOP_COUNT"
		# endregion
		if ! qsc_ps_plugged && type qsc_history_flush_pending >/dev/null 2>&1; then
			# region agent log
			qsc_runtime_trace "H5" "flush_enter" "$QSC_SERVICE_LOOP_COUNT"
			# endregion
			qsc_history_flush_pending
			# region agent log
			_flush_rc="$?"
			qsc_runtime_trace "H5" "flush_exit" "$_flush_rc"
			# endregion
		fi
		# region agent log
		qsc_ps_can_skip_round "$_now"
		_skip_rc="$?"
		qsc_runtime_trace "H1" "skip_result" "$_skip_rc"
		# endregion
		if [ "$_skip_rc" -eq 0 ]; then
			QSC_SERVICE_SKIP_ROUNDS=$((${QSC_SERVICE_SKIP_ROUNDS:-0} + 1))
			QSC_SERVICE_LEAN_IDLE=1
			# 未插电不再发供电状态通知（无充电态可报）
			if type qsc_ps_idle_secs >/dev/null 2>&1; then
				qsc_ps_idle_secs
			else
				QSC_PS_IDLE_EFF="${QSC_PS_IDLE:-30}"
			fi
			qsc_ps_wait "$QSC_PS_IDLE_EFF"
			# region agent log
			_wait_rc="$?"
			qsc_runtime_trace "H1" "wait_exit" "$_wait_rc"
			# endregion
			QSC_PS_SCREEN_CACHE_AT=0
			type qsc_ps_now >/dev/null 2>&1 && qsc_ps_now
			type qsc_service_desc_ondemand_sync >/dev/null 2>&1 &&
				qsc_service_desc_ondemand_sync
			return 0
		fi
		QSC_SERVICE_LEAN_IDLE=0
		[ "$_now" -gt 0 ] 2>/dev/null && QSC_PS_LAST_FULL="$_now"
		# 满轮会自己改简介，快路径的缓存指纹随之失效
		QSC_PS_DESC_SIG=""
		QSC_PS_DESC_STATE_SIG=""
	fi

	QSC_SERVICE_LEAN_IDLE=0
	QSC_SERVICE_FULL_ROUNDS=$((QSC_SERVICE_FULL_ROUNDS + 1))
	# 停充决策属于可恢复的单轮任务，不能让某个 sysfs/系统服务调用把
	# 主循环永久占住；超时后下一轮会继续刷新简介和重新评估。
	# region agent log
	qsc_runtime_trace "H6" "switch_enter" "$QSC_SERVICE_FULL_ROUNDS"
	# endregion
	if type qsc_ps_native_exec >/dev/null 2>&1; then
		qsc_ps_native_exec 45 "$BINDIR/qsc_switch.sh" > /dev/null 2>&1
	else
		"$BINDIR/qsc_switch.sh" > /dev/null 2>&1
	fi
	# region agent log
	_switch_rc="$?"
	qsc_runtime_trace "H6" "switch_exit" "$_switch_rc"
	# endregion
	# qsc_switch 期间电量/供电状态可能已经变化；等待前再刷新一次，
	# 避免 module.prop 在下一次 qscd 唤醒前继续显示旧快照。
	if type qsc_ps_load_conf >/dev/null 2>&1 && type qsc_ps_refresh_desc >/dev/null 2>&1; then
		qsc_ps_load_conf
		qsc_ps_now
		qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
		# region agent log
		qsc_runtime_trace "H8" "post_switch_description" "$?"
		# endregion
	fi
	_sleep="$(cat "$DATADIR/loop_sleep" 2>/dev/null | tr -d ' \r\n')"
	case "$_sleep" in
		""|*[!0-9]*) _sleep=3 ;;
	esac
	[ "$_sleep" -ge 2 ] 2>/dev/null || _sleep=3
	[ "$_sleep" -le 300 ] 2>/dev/null || _sleep=300
	QSC_PS_WAIT_FALLBACK="$_sleep"
	# region agent log
	qsc_runtime_trace "H1" "wait_enter" "$_sleep"
	# endregion
	qsc_ps_wait "$_sleep"
	# region agent log
	_wait_rc="$?"
	qsc_runtime_trace "H1" "wait_exit" "$_wait_rc"
	# endregion
}
