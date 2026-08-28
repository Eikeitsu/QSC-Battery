#!/system/bin/sh
# 停充主循环：读配置/电量 → 判定 → 调用 lib/charge 写节点
. "${0%/*}/common.sh"

if qsc_debug_enabled; then
	echo "$(date +%F_%T) qsc_switch.sh 被调用" >> "$DATADIR/startup.log"
fi
qsc_debug_step 1

# 单键取值走 qsc_conf_scan 的 QSCV_*（无 fork）；多行键仍需原文
config_conf="$(egrep -v '^#' "$CONF" 2>/dev/null)"
qsc_conf_scan
qsc_debug_step 2

if [ ! -f "$CONF" ]; then
	qsc_log_once no_conf error "找不到 config.conf"
fi

# 统一快照：sysfs 优先，只有字段不完整时才调用 dumpsys battery。
# 这样停充决策、模块简介和 WebUI 共享相同的电量/温度/供电语义。
battery_level=""
battery_status=""
battery_powered=""
temperature=""
if qsc_battery_snapshot_read; then
	battery_level="$QSC_BATTERY_LEVEL"
	battery_status="$QSC_BATTERY_STATUS"
	battery_powered="$QSC_BATTERY_POWERED"
	temperature="$QSC_BATTERY_TEMP"
	_sf_status="$QSC_BATTERY_STATUS"
else
	qsc_log_once no_snapshot warn "电池快照不完整，跳过本轮停充评估"
fi
qsc_battery_snapshot_record
qsc_debug_step 3

charge_source="$(qsc_charge_source 2>/dev/null)"
wireless_policy="${QSCV_wireless_policy}"
case "$wireless_policy" in
	same|ignore) ;;
	*) wireless_policy=same ;;
esac
# ignore：仅无线供电时跳过电量/温控/App 停充触发（已停充仍维持）
wireless_skip=0
if [ "$wireless_policy" = "ignore" ] && [ "$charge_source" = "wireless" ]; then
	wireless_skip=1
fi

loop_interval_sec="${QSCV_loop_interval_sec}"
loop_interval_maintain_sec="${QSCV_loop_interval_maintain_sec}"
history_enable="${QSCV_history_enable}"
history_interval_sec="${QSCV_history_interval_sec}"
app_stop="${QSCV_app_stop}"
app_stop_list="${QSCV_app_stop_list}"
app_stop="$(qsc_clamp_int "${app_stop:-0}" 0 1 0)"
history_enable="$(qsc_clamp_int "${history_enable:-1}" 0 1 1)"

charge_full="${QSCV_charge_full}"
power_reset="${QSCV_power_reset}"
Shut_down="${QSCV_Shut_down}"
power_stop="${QSCV_power_stop}"
power_start="${QSCV_power_start}"
temperature_switch="${QSCV_temperature_switch}"
temperature_switch_stop="${QSCV_temperature_switch_stop}"
temperature_switch_start="${QSCV_temperature_switch_start}"

_raw_power_stop="$power_stop"
_raw_power_start="$power_start"
_raw_temp_stop="$temperature_switch_stop"
_raw_temp_start="$temperature_switch_start"

# 配置兜底：拒非法/天文数字，避免误伤设备
charge_full="$(qsc_clamp_int "$charge_full" 0 1 0)"
power_reset="$(qsc_clamp_int "$power_reset" 0 1 0)"
Shut_down="$(qsc_clamp_int "$Shut_down" 0 20 0)"
power_stop="$(qsc_clamp_level_or_off "$power_stop" 100)"
power_start="$(qsc_clamp_int "$power_start" 1 100 95)"
if [ "$power_stop" -le 100 ] 2>/dev/null && [ "$power_stop" -le "$power_start" ] 2>/dev/null; then
	if [ "$power_stop" -gt 5 ] 2>/dev/null; then
		power_start=$((power_stop - 5))
	else
		power_start=1
	fi
fi
temperature_switch="$(qsc_clamp_int "$temperature_switch" 0 1 1)"
temperature_switch_stop="$(qsc_clamp_int "$temperature_switch_stop" 25 70 60)"
temperature_switch_start="$(qsc_clamp_int "$temperature_switch_start" 25 70 50)"
if [ "$temperature_switch_stop" -le "$temperature_switch_start" ] 2>/dev/null; then
	if [ "$temperature_switch_stop" -gt 30 ] 2>/dev/null; then
		temperature_switch_start=$((temperature_switch_stop - 5))
	else
		temperature_switch_start=25
	fi
fi
if [ "$power_stop" != "$_raw_power_stop" ] || [ "$power_start" != "$_raw_power_start" ]; then
	qsc_log_once cfg_pwr warn "电量阈值已纠正 ${_raw_power_stop}/${_raw_power_start} → 停充${power_stop}% 恢复${power_start}%"
fi
if [ "$temperature_switch_stop" != "$_raw_temp_stop" ] || [ "$temperature_switch_start" != "$_raw_temp_start" ]; then
	qsc_log_once cfg_temp warn "温控阈值已纠正 ${_raw_temp_stop}/${_raw_temp_start} → 停充${temperature_switch_stop}°C 恢复${temperature_switch_start}°C"
fi
off_qsc=0
# 低电量安全线：低于它就忽略温控与按 App 停充，强制恢复充电。
# 故意不做成配置项——安全底线不应该能被关掉。
QSC_EMERGENCY_LEVEL=20
qsc_debug_step 5

if [ ! -n "$battery_level" ]; then
	for sysfs_cap in "$PSDIR/battery/capacity" "$PSDIR/bms/capacity" "$PSDIR/battery/soc"; do
		if [ -f "$sysfs_cap" ] && [ -r "$sysfs_cap" ]; then
			battery_level="$(qsc_safe_cat "$sysfs_cap")"
			if [ -n "$battery_level" ]; then
				qsc_log_once batt_src debug "电量来自 sysfs $sysfs_cap=$battery_level"
				break
			fi
		fi
	done
fi
qsc_debug_step 6
if [ -n "$battery_level" ]; then
	rm -f "$DATADIR/no_battery_logged"
fi
if [ ! -n "$battery_level" ]; then
	if [ ! -f "$DATADIR/no_battery_logged" ]; then
		qsc_log error "无法获取电池电量！dumpsys 超时且 sysfs 也读取失败"
		touch "$DATADIR/no_battery_logged"
	fi
	qsc_refresh_module_description
	exit 0
fi

if [ ! -n "$temperature" ]; then
	for sysfs_temp in "$PSDIR/battery/temp" "$PSDIR/bms/temp" "$PSDIR/battery/batt_temp"; do
		if [ -f "$sysfs_temp" ] && [ -r "$sysfs_temp" ]; then
			temperature_raw="$(qsc_safe_cat "$sysfs_temp")"
			temperature="$(qsc_normalize_temperature "$temperature_raw")"
			if [ -n "$temperature" ]; then
				qsc_log_once temp_src debug "温度来自 sysfs $sysfs_temp=${temperature}°C"
				break
			fi
		fi
	done
fi
qsc_debug_step 7
if [ -n "$temperature" ]; then
	rm -f "$DATADIR/no_temp_logged"
fi
if [ ! -n "$temperature" ]; then
	if [ ! -f "$DATADIR/no_temp_logged" ]; then
		qsc_log error "无法获取电池温度！dumpsys 超时且 sysfs 也读取失败"
		touch "$DATADIR/no_temp_logged"
	fi
	qsc_refresh_module_description
	exit 0
fi

if [ -f "$OFF_FLAG" -o -f "$MODDIR/disable" ]; then
	off_qsc=1
	qsc_log_once mod_off warn "充电控制已关闭，跳过停充与电流控制"
	power_stop="110"
	power_start="105"
	temperature_switch="0"
	qsc_stop_wakelock_release
	# active_switch 记着「当初用哪个节点停的」，是还原时最可靠的一条线索。
	# 仍停充时不能在这里抹掉，得留给下面的还原流程用完再清。
	[ -f "$DATADIR/power_switch" ] || qsc_clear_active_switch
	if [ ! -f "$DATADIR/off_d" ]; then
		touch "$DATADIR/off_d"
		rm -f "$DATADIR/now_c" "$DATADIR/power_on" "$DATADIR/power_off" "$DATADIR/current_mode_tag"
	fi
else
	rm -f "$DATADIR/off_d"
	qsc_log_once_clear mod_off
fi

battery_status_data=0
switch_stop_mode=0
log_log=0
cpu_log=0
log_log2=0
cpu_log2=0
full_log=0
reset_log=0
battery_stop_reason=0

if [ ! -f "$LIST_SWITCH" ]; then
	if [ -f "$BINDIR/list_switch.sh" ]; then
		chmod 0755 "$BINDIR/list_switch.sh"
		"$BINDIR/list_switch.sh" > /dev/null 2>&1
		qsc_log_new warn "缺少列表文件，正在创建，请稍等"
		qsc_write_module_description "🔎启动中" "生成开关列表" "$DESC_INTRO"
		exit 0
	fi
	qsc_log_new error "list_switch.sh文件不存在，请重新安装模块重启"
	qsc_write_module_description "⚠️异常" "缺少开关列表" "请重新安装模块并重启"
	exit 0
fi

qsc_build_switch_list

# 每次开机（服务启动）检查一轮残留停充节点。标记由 service.sh 启动时清掉，
# 所以这段每个开机周期只跑一次，不进热路径。
if [ ! -f "$DATADIR/.orphan_checked" ] && type qsc_orphan_stop_check >/dev/null 2>&1; then
	touch "$DATADIR/.orphan_checked"
	qsc_orphan_stop_check || true
fi

# 关掉总开关时先把充电节点还原，再罢工。
# 停充生效期间去关模块，原先会直接跳过 484 行那段恢复流程（它有 off_qsc 门禁），
# 节点就永远停在停充值上：手机再也充不进电，而模块简介显示「已关闭 / 模块未运行」，
# 没人会怀疑到模块头上。放在 qsc_build_switch_list 之后，是因为 qsc_power_start
# 要用它算出的 switch_list 与 QSC_USER_SWITCHES。
if [ "$off_qsc" = "1" ] && [ -f "$DATADIR/power_switch" ]; then
	qsc_power_start
	if [ "$start_ok" = "1" ]; then
		rm -f "$DATADIR/power_switch" "$DATADIR/temp_switch" \
			"$DATADIR/battery_switch" "$DATADIR/app_stop_flag" \
			"$DATADIR/resume_fail_hint"
		qsc_clear_active_switch
		qsc_log info "模块已关闭，还原充电节点并清除停充状态 [$start_node <- $start_val]"
		qsc_log_once_clear off_restore
	else
		# 还原失败要留着标记继续重试，别把「节点仍停着」这件事丢掉
		touch "$DATADIR/resume_fail_hint"
		qsc_log_once off_restore error "模块已关闭但还原充电节点失败，将持续重试"
	fi
fi

qsc_charge_full() {
	if [ "$charge_full" = "1" -a "$battery_level" = "100" -a "$power_stop" = "100" ]; then
		now_current="$(qsc_safe_cat "$PSDIR/battery/current_now")"
		if [ "$battery_status" = "5" ]; then
			rm -f "$DATADIR/now_c"
			qsc_log info "电量$battery_level 触发充满再停功能 当前已充满"
		else
			full_log=1
			if [ -n "$now_current" ]; then
				now_current="$(echo "$now_current" | sed -n 's/-//g;$p')"
				if [ "$now_current" -lt "100000" ]; then
					echo "$now_current" >> "$DATADIR/now_c"
				else
					rm -f "$DATADIR/now_c"
				fi
				now_current_n="$(cat "$DATADIR/now_c" | wc -l)"
				if [ "$now_current_n" -ge "3" ]; then
					full_log=0
					rm -f "$DATADIR/now_c"
					qsc_log debug "电量$battery_level 触发充满再停功能 当前电流$now_current"
				fi
			fi
		fi
	fi
}

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

# 按 App 停充命中。前台检测要跑 ps / dumpsys window，是本模块最贵的一步：
# 只在「该评估停充」或「已因 App 停充需维持」时执行，且至少间隔
# QSC_APP_STOP_MIN_GAP 秒，中间沿用上轮缓存结果。
# 注意：已停充时 status 会变成 Not charging，若此时不检测会误判应用已退出而恢复充电；
# 拔掉充电器后不再检测，标记会在恢复流程里清掉，下次插电重新判定。
QSC_APP_STOP_MIN_GAP=10
app_stop_hit=0
if [ "$app_stop" = "1" ] && [ -n "$app_stop_list" ] \
	&& { [ "$charge_eval" = "1" ] \
		|| { [ -n "$battery_powered" ] && [ -f "$DATADIR/app_stop_flag" ]; }; }; then
	_as_now="$(date +%s 2>/dev/null)"
	_as_last=""
	qsc_read_node "$DATADIR/app_stop_ts" && _as_last="$QSC_NODE_VAL"
	case "$_as_last" in ""|*[!0-9]*) _as_last=0 ;; esac
	if [ -n "$_as_now" ] && [ "$((_as_now - _as_last))" -lt "$QSC_APP_STOP_MIN_GAP" ] 2>/dev/null; then
		[ -f "$DATADIR/app_stop_cache" ] && app_stop_hit=1
	else
		qsc_write_pkg_tmp "$app_stop_list" "$DATADIR/.app_stop_list"
		if qsc_pkg_list_hit "$DATADIR/.app_stop_list"; then
			app_stop_hit=1
			touch "$DATADIR/app_stop_cache"
		else
			rm -f "$DATADIR/app_stop_cache"
		fi
		rm -f "$DATADIR/.app_stop_list"
		[ -n "$_as_now" ] && echo "$_as_now" >"$DATADIR/app_stop_ts" 2>/dev/null
	fi
elif [ "$app_stop" != "1" ]; then
	rm -f "$DATADIR/app_stop_cache" "$DATADIR/app_stop_ts" 2>/dev/null
fi

if [ "$charge_eval" = "1" ]; then
	if [ -f "$LOG_FILE" ]; then
		log_n="$(cat "$LOG_FILE" | wc -l)"
		if [ "$log_n" -gt "80" ]; then
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
		# 首次停充；若 status 仍为充电中说明未粘住，仅对 MCA/preferred 或首次后再试写
		if [ "$first_stop" = "1" ]; then
			qsc_power_stop
		else
			# status 仍 Charging：系统改回了节点。MCA/preferred 重申；通用节点再写一次 active
			if ! qsc_mca_write stop; then
				qsc_load_device_profile 2>/dev/null || true
				if [ "${QSC_REASSERT:-0}" = "1" ] && qsc_pref_write stop; then
					:
				else
					qsc_reaffirm_active_stop || qsc_power_stop
				fi
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
				elif [ -f "$DATADIR/app_stop_flag" ] && [ "$battery_stop_reason" != "1" ]; then
					qsc_log info "电量$battery_level 按 App 停充 [$stop_nodes]"
					qsc_notify qsc_stop "充电控制" "前台应用触发停充 · 电量 ${battery_level}%"
				else
					qsc_log info "电量$battery_level 停止充电 [$stop_nodes]"
					qsc_notify qsc_stop "充电控制" "已停充 · 电量 ${battery_level}%"
				fi
			fi
		elif [ "$first_stop" = "1" ]; then
			if [ ! -f "$DATADIR/no_node_logged" ]; then
				qsc_log error "电量$battery_level 未找到有效充电控制节点！请插电后在 Action 测开关，或执行 bin/test_switch.sh"
				touch "$DATADIR/no_node_logged"
				touch "$DATADIR/stop_fail_hint"
				qsc_notify qsc_fail "充电控制" "停充失败：未找到有效节点，请插电测开关"
			fi
		fi
		if [ -f "$DATADIR/power_switch" -a "$battery_stop_reason" = "1" ]; then
			touch "$DATADIR/battery_switch"
		fi
	else
		reset_log=1
	fi
	if [ ! -f "$DATADIR/power_on" -a "$off_qsc" != "1" ]; then
		rm -f "$DATADIR/power_off"
		touch "$DATADIR/power_on"
		if [ "$power_reset" = "1" -a "$reset_log" = "1" ]; then
			qsc_power_reset
			qsc_log info "电量$battery_level 触发自动拔插功能"
		fi
	fi
else
	# 已停充：插电期间单节点重申 + 按需持锁（模块关闭时不维持停充）
	if [ -f "$DATADIR/power_switch" ] && [ "$off_qsc" != "1" ]; then
		qsc_maintain_stop_while_plugged
	else
		qsc_stop_wakelock_release
	fi
	if [ ! -f "$DATADIR/power_off" -a "$off_qsc" != "1" ]; then
		rm -f "$DATADIR/now_c" "$DATADIR/power_on"
		touch "$DATADIR/power_off"
	fi
	# 拔掉充电器：没有充电器就无所谓「停充」，此处必须还原节点并清标记。
	# 之前只有「电量降到恢复阈值以下」才会走 462 行的恢复流程，于是在阈值以上
	# 拔线后 power_switch 会一直留着，后果有三个：
	#   1) 模块简介一直停在「⏸️已停充 / 电量降至 X% 后恢复」，跟着的电量温度也不再变；
	#   2) qsc_ps_can_skip_round 见到 power_switch 就不跳轮，主循环按维持间隔空转，
	#      省电模式形同失效；
	#   3) MCA 机型再插上时 status 仍报 Not charging，而 power_switch 还在，
	#      charge_eval 进不去，停充直接失灵。
	#
	# 但「看起来没在供电」远不等于「线拔了」：本模块的停充手段里有端口 suspend
	# 与电流墙，写下去之后 online 掉 0、status 也可能变 Discharging，和拔线难以
	# 区分。曾因此在阈值处反复启停（到 100% 停充，下一轮误判拔线又还原，立刻重充）。
	# 所以这里要 qsc_charger_really_gone 拿到「线确实不在」的证据，
	# 且连续两轮都这么判定才动手，避免停充瞬间的信号抖动。
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
		qsc_power_start
		if [ "$start_ok" = "1" ]; then
			rm -f "$DATADIR/power_switch" "$DATADIR/temp_switch" \
				"$DATADIR/battery_switch" "$DATADIR/app_stop_flag" \
				"$DATADIR/resume_fail_hint"
			qsc_clear_active_switch
			qsc_stop_wakelock_release
			qsc_log info "已拔出充电器，还原充电节点并清除停充状态 [$start_node <- $start_val]"
			qsc_log_once_clear unplug_restore
			qsc_log_once_clear resume_fail
		else
			# 还原失败时保留标记，交给恢复流程继续重试，避免节点停在停充态却没人管
			touch "$DATADIR/resume_fail_hint"
			qsc_log_once unplug_restore warn "拔出充电器后还原充电节点失败，将持续重试"
		fi
	fi
fi

if [ -f "$DATADIR/power_switch" ] && [ "$off_qsc" != "1" ]; then
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
			else
				qsc_log info "电量$battery_level 恢复充电 [$start_node <- $start_val]"
				qsc_notify qsc_resume "充电控制" "已恢复充电 · 电量 ${battery_level}%"
			fi
		fi
	fi
fi

# 供电开关未停充时，若已安装电流控制组件则应用策略（兼容模式跳过，避免与其它限流模块抢写）
# 同样只在「该评估充电」时写，避免停充后仍写电流节点与小米充电服务互抢
Compatibility_mode="${QSCV_Compatibility_mode}"
[ -n "$Compatibility_mode" ] || Compatibility_mode=0
if [ -f "$DATADIR/compat_hint" ] && [ "$Compatibility_mode" != "1" ]; then
	_ch="$(cat "$DATADIR/compat_hint" 2>/dev/null | tr -d '\r\n')"
	[ -n "$_ch" ] && qsc_log_once compat_mod warn "检测到其它充电/限流模块($_ch)，建议开启兼容模式"
fi
if [ "$charge_eval" = "1" ] && [ ! -f "$DATADIR/power_switch" ] && [ "$off_qsc" != "1" ]; then
	if [ "$Compatibility_mode" = "1" ]; then
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

qsc_debug_step 9
#version=20260805
# ##
