#!/system/bin/sh
# switch: apply resume / current / description

if [ -f "$DATADIR/power_switch" ] && [ "$module_off" != "1" ]; then
	temp_ready=1
	battery_ready=1
	app_ready=1
	if [ -f "$DATADIR/temp_switch" ]; then
		if [ "$temperature_switch" = "1" -a -n "$temperature_switch_start" -a "$temperature" -gt "$temperature_switch_start" ]; then
			temp_ready=0
		else
			cpu_log2=1
		fi
	fi
	if [ -f "$DATADIR/battery_switch" ]; then
		if [ "$power_stop" -le "100" -a "$power_stop" -gt "$power_start" -a "$battery_level" -gt "$power_start" ]; then
			# 仍高于恢复电量：仅在停充时段内继续维持；时段外允许恢复
			if qsc_power_stop_schedule_active; then
				battery_ready=0
			fi
		fi
	elif [ "$power_stop" -le "100" -a "$power_stop" -gt "$power_start" -a "$battery_level" -gt "$power_start" ]; then
		# 无原因标记的旧状态保守按电量停充处理，避免升级后在高电量误恢复
		if qsc_power_stop_schedule_active; then
			battery_ready=0
		fi
	fi
	if [ -f "$DATADIR/app_stop_flag" ]; then
		if [ "$app_stop" = "1" ] && [ "$app_stop_hit" = "1" ]; then
			app_ready=0
		fi
	fi
	# 低电量紧急恢复：温控与按 App 停充这两个 latch 只看温度/进程，
	# 条件不消失就一直不恢复，手机能被一路锁到 0% 充不进电。
	# 低于安全线时无条件放行，先保证充上。
	# 故意不覆盖 battery_ready：那是用户自己设的停充/恢复电量（有人会把
	# power_start 设成 10%），紧急线不该去推翻显式配置。
	if [ "$battery_level" -le "$QSC_EMERGENCY_LEVEL" ] 2>/dev/null; then
		if [ "$temp_ready" = "0" ] || [ "$app_ready" = "0" ]; then
			qsc_log_once emerg_resume warn \
				"电量$battery_level 已低于安全线 ${QSC_EMERGENCY_LEVEL}%，忽略温控/应用停充，强制恢复充电"
			qsc_notify qsc_resume "充电控制" "电量过低（${battery_level}%），已强制恢复充电"
			type qsc_event_warn >/dev/null 2>&1 &&
				qsc_event_warn "低电量紧急恢复（≤${QSC_EMERGENCY_LEVEL}%）"
		fi
		temp_ready=1
		app_ready=1
	fi
	if [ "$temp_ready" = "1" -a "$battery_ready" = "1" -a "$app_ready" = "1" ]; then
		sleep 3
		qsc_power_start
		if [ "$start_ok" = "1" ]; then
			rm -f "$DATADIR/power_switch" "$DATADIR/temp_switch" "$DATADIR/battery_switch" "$DATADIR/app_stop_flag"
			rm -f "$DATADIR/resume_fail_hint"
			rm -f "$DATADIR/charge_full_done" "$DATADIR/charge_full_since" "$DATADIR/now_c"
			qsc_clear_active_switch
			qsc_stop_wakelock_release
			qsc_log_once_clear resume_fail
		else
			# 还原失败在这里原先完全静默：标记留着、节点还停着、用户只看到充不进电
			touch "$DATADIR/resume_fail_hint"
			qsc_log_once resume_fail error "已满足恢复条件但还原充电节点失败，将持续重试"
		fi
		if [ "$log_log2" = "1" ]; then
			if [ "$cpu_log2" = "1" ]; then
				qsc_log info "电量$battery_level 触发开关温控：恢复充电 温度$temperature [$start_node <- $start_val]"
				qsc_notify qsc_resume "充电控制" "温度恢复充电 ${temperature}°C · 电量 ${battery_level}%"
				type qsc_event_start >/dev/null 2>&1 &&
					qsc_event_start "温度恢复 ${temperature}°C"
			else
				qsc_log info "电量$battery_level 恢复充电 [$start_node <- $start_val]"
				qsc_notify qsc_resume "充电控制" "已恢复充电 · 电量 ${battery_level}%"
				type qsc_event_start >/dev/null 2>&1 &&
					qsc_event_start "恢复充电"
			fi
		fi
	fi
fi

# 供电开关未停充时，若已安装电流控制组件则应用策略（兼容模式跳过，避免与其它限流模块抢写）
# 同样只在「该评估充电」时写，避免停充后仍写电流节点与小米充电服务互抢
compatibility_mode="${QSCV_compatibility_mode}"
[ -n "$compatibility_mode" ] || compatibility_mode=0
if [ -f "$DATADIR/compat_hint" ] && [ "$compatibility_mode" != "1" ]; then
	_ch="$(cat "$DATADIR/compat_hint" 2>/dev/null | tr -d '\r\n')"
	[ -n "$_ch" ] && qsc_log_once compat_mod warn "检测到其它充电/限流模块($_ch)，建议开启兼容模式"
fi
if [ "$charge_eval" = "1" ] && [ ! -f "$DATADIR/power_switch" ] && [ "$module_off" != "1" ]; then
	if [ "$compatibility_mode" = "1" ]; then
		qsc_log_once compat warn "兼容模式开启，已跳过电流控制"
		rm -f "$DATADIR/current_mode_tag"
		rm -f "$DATADIR/current_reaffirm_ts" "$DATADIR/current_drift_streak"
		if type qsc_bypass_hw_off >/dev/null 2>&1; then
			qsc_bypass_hw_off
		fi
	elif type qsc_apply_current_control >/dev/null 2>&1; then
		qsc_log_once_clear compat
		# 电流控制开启且探测列表为空时，充电中重探测
		_cc="$(qsc_current_conf_get current_control 2>/dev/null)"
		if [ "$_cc" = "1" ] \
			&& [ ! -s "${CH_CURR_CTRL_FILES:-$DATADIR/ch_curr_ctrl_files}" ] \
			&& type qsc_current_is_charging >/dev/null 2>&1 \
			&& qsc_current_is_charging \
			&& type qsc_current_probe_ctrl_files >/dev/null 2>&1; then
			qsc_current_probe_ctrl_files
		fi
		qsc_apply_current_control
	elif [ -f "$CURRENT_CONF" ]; then
		qsc_log_once no_cc error "存在 current.json 但缺少 current.sh，请重新安装并勾选电流控制"
	fi
elif [ "$charge_eval" != "1" ]; then
	rm -f "$DATADIR/current_mode_tag"
	rm -f "$DATADIR/current_reaffirm_ts" "$DATADIR/current_drift_streak"
	if type qsc_bypass_hw_off >/dev/null 2>&1; then
		qsc_bypass_hw_off
	fi
fi

# 历史采样 + 循环间隔
if type qsc_history_sample >/dev/null 2>&1; then
	qsc_history_sample "$history_enable" "$history_interval_sec" "$battery_level" "$temperature"
fi
if type qsc_health_sample_daily >/dev/null 2>&1; then
	qsc_health_sample_daily
fi
if type qsc_ps_load_conf >/dev/null 2>&1; then
	qsc_ps_load_conf
	_plugged=0
	[ -n "$battery_powered" ] && _plugged=1
	_temp_stop=""
	[ "$temperature_switch" = "1" ] && _temp_stop="$temperature_switch_stop"
	qsc_write_loop_sleep_value \
		"$(qsc_ps_next_sleep "$battery_level" "$power_stop" "$_plugged" \
			"$temperature" "$_temp_stop")"
elif type qsc_write_loop_sleep >/dev/null 2>&1; then
	qsc_write_loop_sleep "$loop_interval_sec" "$loop_interval_maintain_sec"
fi

qsc_refresh_module_description
type qsc_notify_power_status >/dev/null 2>&1 && qsc_notify_power_status

qsc_debug_step 9
#version=20260805
# ##
