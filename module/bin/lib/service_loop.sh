#!/system/bin/sh
# service: one loop iteration (defined as function so `return` replaces sourced `continue`)

qsc_service_loop_once() {
	QSC_SERVICE_LOOP_COUNT=$((QSC_SERVICE_LOOP_COUNT + 1))
	qsc_hot_finalize_maybe
	# 省电快路径：未插电且未维持停充时，本轮只读几个 online 节点就睡，
	# 不 fork qsc_switch.sh（那会重新解析约 90KB 脚本并触发多次写盘）。
	if type qsc_ps_load_conf >/dev/null 2>&1; then
		qsc_ps_load_conf
		qsc_ps_now
		_now="$QSC_PS_NOW"
		# region agent log
		qsc_runtime_trace "H1" "loop_enter" "$QSC_SERVICE_LOOP_COUNT:$_now"
		# endregion
		qsc_service_heartbeat
		# 即使本轮准备跳过 qsc_switch，也要用当前供电状态刷新模块简介。
		if type qsc_ps_refresh_desc >/dev/null 2>&1; then
			qsc_ps_refresh_desc "$_now"
		fi
		# region agent log
		qsc_runtime_trace "H1" "after_description" "$QSC_SERVICE_LOOP_COUNT"
		# endregion
		# 拔电后立即落盘未满批次的充电采样，避免最近几条电流数据只留在
		# pending 文件里；仍在充电时不调用，保持批量写盘的省电收益。
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
			if type qsc_notify_power_status >/dev/null 2>&1; then
				qsc_notify_power_status
			fi
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
			return 0
		fi
		[ "$_now" -gt 0 ] 2>/dev/null && QSC_PS_LAST_FULL="$_now"
		# 满轮会自己改简介，快路径的缓存指纹随之失效
		QSC_PS_DESC_SIG=""
	fi

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
