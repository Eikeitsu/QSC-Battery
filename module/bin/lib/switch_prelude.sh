#!/system/bin/sh
# switch: conf / snapshot / early exits
# （由 qsc_switch.sh 在 common.sh 之后 source）

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
description_enable="$(qsc_clamp_int "${QSCV_description_enable:-1}" 0 1 1)"

charge_full="${QSCV_charge_full}"
charge_full_mode="${QSCV_charge_full_mode}"
charge_full_wait_sec="${QSCV_charge_full_wait_sec}"
power_reset="${QSCV_power_reset}"
unplug_restore="${QSCV_unplug_restore}"
shut_down="${QSCV_shut_down}"
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
case "$charge_full_mode" in
	time|TIME) charge_full_mode="time" ;;
	auto|AUTO) charge_full_mode="auto" ;;
	*) charge_full_mode="current" ;;
esac
charge_full_wait_sec="$(qsc_clamp_int "${charge_full_wait_sec:-600}" 60 3600 600)"
power_reset="$(qsc_clamp_int "$power_reset" 0 1 0)"
unplug_restore="$(qsc_clamp_int "${unplug_restore:-1}" 0 1 1)"
shut_down="$(qsc_clamp_int "$shut_down" 0 20 0)"
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
module_off=0
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

if [ -f "$MODULE_OFF_FLAG" -o -f "$MODDIR/disable" ]; then
	module_off=1
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
# 停充生效期间去关模块，原先会直接跳过 484 行那段恢复流程（它有 module_off 门禁），
# 节点就永远停在停充值上：手机再也充不进电，而模块简介显示「已关闭 / 模块未运行」，
# 没人会怀疑到模块头上。放在 qsc_build_switch_list 之后，是因为 qsc_power_start
# 要用它算出的 switch_list 与 QSC_USER_SWITCHES。
if [ "$module_off" = "1" ] && [ -f "$DATADIR/power_switch" ]; then
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
