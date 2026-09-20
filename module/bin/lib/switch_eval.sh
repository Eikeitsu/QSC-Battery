#!/system/bin/sh
# switch: stop/start decision

qsc_debug_step 8
# status 为充电中(2)/已满(5)
if [ "$battery_status" = "2" -o "$battery_status" = "5" ]; then
	battery_status_data=1
fi

# 是否该评估停充/电流控制。
# 光看 status=2/5 不够：MCA 机型（红米K90U 等）充电由 mca_charger 接管，
# battery/status 插电充电时也可能一直报 Not charging，那样停充分支永远进不去。
# 光看插电也不行：本模块停充后 status 会变 Not charging，每轮再全量重写开关
# 会在小米上与系统互抢闪充。
# 故取两者之一：status 明确在充电，或当前并非本模块停充的状态。
charge_eval=0
if [ -n "$battery_powered" ]; then
	if [ "$battery_status_data" = "1" ] || [ ! -f "$DATADIR/power_switch" ]; then
		charge_eval=1
	fi
fi
if [ "$charge_eval" = "1" ] && [ "$battery_status_data" != "1" ]; then
	qsc_log_once st_odd debug "插电但 status=${battery_status:-?}（非充电中），仍按供电评估停充"
fi
if qsc_debug_enabled; then
	_dbg_online=""
	_dbg_present=""
	_dbg_type=""
	_dbg_vbus=""
	qsc_read_node "$PSDIR/usb/online" && _dbg_online="$QSC_NODE_VAL"
	qsc_read_node "$PSDIR/usb/present" && _dbg_present="$QSC_NODE_VAL"
	qsc_read_node "$PSDIR/usb/type" && _dbg_type="$QSC_NODE_VAL"
	qsc_read_node "$PSDIR/usb/voltage_now" && _dbg_vbus="$QSC_NODE_VAL"
	qsc_log_once mca_decision debug \
		"停充评估：level=$battery_level stop=$power_stop status=$battery_status raw_status=${_sf_status:-?} powered=$([ -n "$battery_powered" ] && echo 1 || echo 0) eval=$charge_eval switch=$([ -f "$DATADIR/power_switch" ] && echo 1 || echo 0) mca=$(qsc_profile_get mca 2>/dev/null) mca_path=$(qsc_profile_get mca_path 2>/dev/null) usb_online=${_dbg_online:-?} usb_present=${_dbg_present:-?} usb_type=${_dbg_type:-?} usb_vbus=${_dbg_vbus:-?}"
fi

# 按 App 停充命中。前台检测走统一总线（XP 优先）；进程检测仍可能用 ps/qscd pkgs。
# 有缓存窗口，避免主循环每轮都打。
# App 停充：列表命中经墓碑会话（约 1s 进 / 30s 离），避免闪切反复停充/恢复。
# 有 XP 时以前台为准；无 XP 走列表命中（含进程弱退回）。
# 注意：已停充时 status 会变成 Not charging，若此时不检测会误判应用已退出而恢复充电；
# 拔掉充电器后不再检测，标记会在恢复流程里清掉，下次插电重新判定。
app_stop_hit=0
if [ "$app_stop" = "1" ] && [ -n "$app_stop_list" ] \
	&& { [ "$charge_eval" = "1" ] \
		|| { [ -n "$battery_powered" ] && [ -f "$DATADIR/app_stop_flag" ]; }; }; then
	qsc_write_pkg_tmp "$app_stop_list" "$DATADIR/.app_stop_list"
	_as_raw=0
	if type qsc_fg_xp_trust_file >/dev/null 2>&1 && qsc_fg_xp_trust_file; then
		type qsc_fg_list_raw_hit >/dev/null 2>&1 &&
			qsc_fg_list_raw_hit "$DATADIR/.app_stop_list" && _as_raw=1
	else
		if type qsc_pkg_list_hit >/dev/null 2>&1 && qsc_pkg_list_hit "$DATADIR/.app_stop_list"; then
			_as_raw=1
		fi
	fi
	if type qsc_fg_session_apply >/dev/null 2>&1; then
		if qsc_fg_session_apply "$DATADIR/app_stop_sess" "$_as_raw"; then
			app_stop_hit=1
		fi
	else
		[ "$_as_raw" = "1" ] && app_stop_hit=1
	fi
	rm -f "$DATADIR/.app_stop_list"
elif [ "$app_stop" != "1" ]; then
	rm -f "$DATADIR/app_stop_cache" "$DATADIR/app_stop_ts" "$DATADIR/app_stop_fg_tok" \
		"$DATADIR/app_stop_sess.on" "$DATADIR/app_stop_sess.last" \
		"$DATADIR/app_stop_sess.enter_at" 2>/dev/null
fi

if [ "$charge_eval" = "1" ]; then
	if type qsc_trim_file_lines >/dev/null 2>&1; then
		qsc_trim_file_lines "$LOG_FILE" 400 300
	elif [ -f "$LOG_FILE" ]; then
		log_n="$(wc -l <"$LOG_FILE" 2>/dev/null | tr -d ' ')"
		case "$log_n" in ""|*[!0-9]*) log_n=0 ;; esac
		if [ "$log_n" -gt 80 ] 2>/dev/null; then
			sed -i '1,10d' "$LOG_FILE"
		fi
	fi
	if [ "$wireless_skip" != "1" ]; then
		if [ "$temperature_switch" = "1" ]; then
			if [ "$temperature_switch_stop" -gt "$temperature_switch_start" -a "$temperature" -ge "$temperature_switch_stop" ]; then
				touch "$DATADIR/temp_switch"
				cpu_log=1
			fi
		fi
		if [ "$power_stop" -gt "$power_start" -a "$battery_level" -ge "$power_stop" ]; then
			# 配置了停充时段时，仅时段内触发电量停充
			if qsc_power_stop_schedule_active; then
				qsc_charge_full
				if [ "$full_log" = "0" ]; then
					switch_stop_mode=1
					battery_stop_reason=1
				fi
			fi
		fi
		if [ "$app_stop_hit" = "1" ]; then
			switch_stop_mode=1
			touch "$DATADIR/app_stop_flag"
		fi
	fi
	if [ "$switch_stop_mode" = "1" -o "$cpu_log" = "1" ]; then
		first_stop=0
		if [ ! -f "$DATADIR/power_switch" ]; then
			first_stop=1
		fi
		if [ "$cpu_log" = "0" -a "$charge_full" != "1" -a "$first_stop" = "1" ]; then
			power_stop_time="${QSCV_power_stop_time}"
			power_stop_time="$(qsc_clamp_int "$power_stop_time" 1 120 3)"
			if [ "$power_stop_time" -gt "0" ]; then
				qsc_log debug "电量$battery_level 延时功能 继续充电$power_stop_time秒 倒计时中"
				sleep "$power_stop_time"
			fi
		fi
		sleep 3
		# switch_batch_blind=1（默认）：每轮全量重申；=0：首次写节点，其后只重申生效节点
		_batch="${QSCV_switch_batch_blind:-1}"
		_batch="$(qsc_clamp_int "$_batch" 0 1 1)"
		if [ "$first_stop" = "1" ] || [ "$_batch" = "1" ]; then
			qsc_power_stop
		else
			if ! qsc_mca_write stop; then
				qsc_load_device_profile 2>/dev/null || true
				if ! qsc_pref_write stop; then
					if ! qsc_reaffirm_active_stop; then
						qsc_maintain_stop_while_plugged
					fi
				fi
			fi
			# 已在停充态：维持标记，避免重申失败被当成「没停充」
			if [ -f "$DATADIR/power_switch" ]; then
				stop_ok=1
			fi
		fi
		if [ "$stop_ok" = "1" ]; then
			touch "$DATADIR/power_switch"
			qsc_stop_wakelock_acquire
			rm -f "$DATADIR/no_node_logged" "$DATADIR/stop_fail_hint"
			# 又能成功停充说明节点是通的，之前那次还原失败的提示不该再挂着
			rm -f "$DATADIR/resume_fail_hint"
			qsc_log_once_clear resume_fail
			# 记下停充时刻：紧接其后的「像是拔线了」大概率是停充自己造成的
			date +%s >"$DATADIR/power_stop_ts" 2>/dev/null
			rm -f "$DATADIR/unplug_streak" 2>/dev/null
			if [ "$battery_stop_reason" = "1" ]; then
				touch "$DATADIR/battery_switch"
			fi
			if [ "$first_stop" = "1" -a "$log_log" = "1" ]; then
				if [ "$cpu_log" = "1" ]; then
					qsc_log info "电量$battery_level 触发开关温控：停止充电 温度$temperature [$stop_nodes]"
					qsc_notify qsc_stop "充电控制" "温度停充 ${temperature}°C · 电量 ${battery_level}%"
					type qsc_event_thermal >/dev/null 2>&1 &&
						qsc_event_thermal "温度停充 ${temperature}°C [$stop_nodes]"
				elif [ -f "$DATADIR/app_stop_flag" ] && [ "$battery_stop_reason" != "1" ]; then
					qsc_log info "电量$battery_level 按 App 停充 [$stop_nodes]"
					qsc_notify qsc_stop "充电控制" "前台应用触发停充 · 电量 ${battery_level}%"
					type qsc_event_stop >/dev/null 2>&1 &&
						qsc_event_stop "应用停充 [$stop_nodes]"
				else
					qsc_log info "电量$battery_level 停止充电 [$stop_nodes]"
					qsc_notify qsc_stop "充电控制" "已停充 · 电量 ${battery_level}%"
					type qsc_event_stop >/dev/null 2>&1 &&
						qsc_event_stop "电量停充 [$stop_nodes]"
				fi
			fi
		elif [ "$first_stop" = "1" ]; then
			if [ ! -f "$DATADIR/no_node_logged" ]; then
				qsc_log error "电量$battery_level 未找到有效充电控制节点！请插电后在 Action 测开关，或执行 bin/test_switch.sh"
				touch "$DATADIR/no_node_logged"
				touch "$DATADIR/stop_fail_hint"
				qsc_notify qsc_fail "充电控制" "停充失败：未找到有效节点，请插电测开关"
				type qsc_event_warn >/dev/null 2>&1 &&
					qsc_event_warn "停充失败：无有效节点"
			fi
		fi
		if [ -f "$DATADIR/power_switch" -a "$battery_stop_reason" = "1" ]; then
			touch "$DATADIR/battery_switch"
		fi
	else
		reset_log=1
	fi
	if [ ! -f "$DATADIR/power_on" -a "$module_off" != "1" ]; then
		rm -f "$DATADIR/power_off"
		touch "$DATADIR/power_on"
		type qsc_event_plug >/dev/null 2>&1 &&
			qsc_event_plug "检测到充电器接入"
		if [ "$power_reset" = "1" -a "$reset_log" = "1" ]; then
			qsc_power_reset
			qsc_log info "电量$battery_level 触发自动拔插功能"
		fi
	fi
else
	# 已停充：插电期间单节点重申 + 按需持锁（模块关闭时不维持停充）
	if [ -f "$DATADIR/power_switch" ] && [ "$module_off" != "1" ]; then
		qsc_maintain_stop_while_plugged
	else
		qsc_stop_wakelock_release
	fi
	if [ ! -f "$DATADIR/power_off" -a "$module_off" != "1" ]; then
		rm -f "$DATADIR/now_c" "$DATADIR/power_on"
		touch "$DATADIR/power_off"
	fi
	# 拔掉充电器：默认还原节点并清标记；unplug_restore=0 时保留停充迟滞（再插上仍停到恢复阈值）。
	# 「看起来没在供电」远不等于「线拔了」：停充写端口 suspend / 电流墙后 online 可能掉 0，
	# 需 qsc_charger_really_gone 且连续两轮才动手。
	unplug_ok=0
	if [ -z "$battery_powered" ] && [ -f "$DATADIR/power_switch" ]; then
		if qsc_charger_really_gone; then
			_us=""
			qsc_read_node "$DATADIR/unplug_streak" && _us="$QSC_NODE_VAL"
			case "$_us" in ""|*[!0-9]*) _us=0 ;; esac
			_us=$((_us + 1))
			echo "$_us" >"$DATADIR/unplug_streak" 2>/dev/null
			[ "$_us" -ge 2 ] 2>/dev/null && unplug_ok=1
		else
			rm -f "$DATADIR/unplug_streak" 2>/dev/null
		fi
	else
		rm -f "$DATADIR/unplug_streak" 2>/dev/null
	fi
	if [ "$unplug_ok" = "1" ]; then
		rm -f "$DATADIR/unplug_streak" 2>/dev/null
		if [ "$unplug_restore" = "0" ]; then
			# 不清 power_switch / 不还原节点：再插上仍保持停充直到恢复阈值
			qsc_log info "已拔出充电器，保留停充状态（未还原节点）"
			type qsc_event_unplug >/dev/null 2>&1 &&
				qsc_event_unplug "充电器拔出，保留停充状态"
			qsc_log_once_clear unplug_restore
		else
			qsc_power_start
			if [ "$start_ok" = "1" ]; then
				rm -f "$DATADIR/power_switch" "$DATADIR/temp_switch" \
					"$DATADIR/battery_switch" "$DATADIR/app_stop_flag" \
					"$DATADIR/resume_fail_hint"
				qsc_clear_active_switch
				qsc_stop_wakelock_release
				qsc_log info "已拔出充电器，还原充电节点并清除停充状态 [$start_node <- $start_val]"
				type qsc_event_unplug >/dev/null 2>&1 &&
					qsc_event_unplug "充电器拔出，已还原节点"
				qsc_log_once_clear unplug_restore
				qsc_log_once_clear resume_fail
			else
				# 还原失败时保留标记，交给恢复流程继续重试，避免节点停在停充态却没人管
				touch "$DATADIR/resume_fail_hint"
				qsc_log_once unplug_restore warn "拔出充电器后还原充电节点失败，将持续重试"
				type qsc_event_warn >/dev/null 2>&1 &&
					qsc_event_warn "拔线后还原节点失败"
			fi
		fi
	fi
fi
