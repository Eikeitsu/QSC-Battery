#!/system/bin/sh
# 停充主循环：读配置/电量 → 判定 → 调用 lib/charge 写节点
. "${0%/*}/common.sh"

echo "$(date +%F_%T) qsc_switch.sh 被调用" >> "$DATADIR/startup.log"
qsc_debug_step 1

config_conf="$(cat "$CONF" | egrep -v '^#')"
qsc_debug_step 2

if [ ! -f "$CONF" ]; then
	qsc_log_once no_conf error "找不到 config.conf"
fi

dumpsys battery > "$DATADIR/.dumpsys_tmp" 2>/dev/null &
dumpsys_pid=$!
for wait_i in 1 2 3 4 5; do
	if [ ! -d "/proc/$dumpsys_pid" ]; then break; fi
	sleep 1
done
if [ -d "/proc/$dumpsys_pid" ]; then
	qsc_log_once dumpsys_to warn "dumpsys battery 超时，改用 sysfs"
	qsc_log_once_clear dumpsys_ok
else
	qsc_log_once dumpsys_ok debug "dumpsys battery 读取成功"
	qsc_log_once_clear dumpsys_to
fi
kill $dumpsys_pid 2>/dev/null
dumpsys_battery="$(cat "$DATADIR/.dumpsys_tmp" 2>/dev/null)"
qsc_debug_step 3
rm -f "$DATADIR/.dumpsys_tmp"

# Android 16+ dumpsys 可能多处含 level:，取首个行首字段，避免 sed $p 取到错误值
battery_level="$(qsc_dumpsys_level "$dumpsys_battery")"
battery_powered="$(echo "$dumpsys_battery" | egrep 'powered: true')"
battery_status="$(echo "$dumpsys_battery" | egrep 'status: ' | sed -n 's/.*status: //g;$p')"
qsc_debug_step 4

if [ ! -n "$battery_powered" ] || [ ! -n "$battery_status" ]; then
	sysfs_status="$(qsc_safe_cat /sys/class/power_supply/battery/status)"
	if [ -n "$sysfs_status" ]; then
		qsc_log_once batt_st debug "充电状态来自 sysfs status=$sysfs_status"
		case "$sysfs_status" in
			Charging) battery_status="2"; battery_powered="powered: true" ;;
			Full) battery_status="5"; battery_powered="powered: true" ;;
			Discharging) battery_status="3"; battery_powered="" ;;
			"Not charging") battery_status="4"; battery_powered="" ;;
		esac
	fi
fi
if [ ! -n "$battery_powered" ]; then
	for usb_online in /sys/class/power_supply/usb/online /sys/class/power_supply/qc_usb/online; do
		if [ -f "$usb_online" ] && [ "$(qsc_safe_cat "$usb_online")" = "1" ]; then
			battery_powered="powered: true"
			battery_status="${battery_status:-2}"
			qsc_log_once usb_on debug "插电状态来自 $usb_online=1"
			break
		fi
	done
fi

charge_full="$(echo "$config_conf" | egrep '^charge_full=' | sed -n 's/charge_full=//g;$p')"
power_reset="$(echo "$config_conf" | egrep '^power_reset=' | sed -n 's/power_reset=//g;$p')"
Shut_down="$(echo "$config_conf" | egrep '^Shut_down=' | sed -n 's/Shut_down=//g;$p')"
temperature_raw="$(echo "$dumpsys_battery" | egrep 'temperature: ' | sed -n 's/.*temperature: //g;$p')"
temperature="$(qsc_normalize_temperature "$temperature_raw")"
power_stop="$(echo "$config_conf" | egrep '^power_stop=' | sed -n 's/power_stop=//g;$p')"
power_start="$(echo "$config_conf" | egrep '^power_start=' | sed -n 's/power_start=//g;$p')"
temperature_switch="$(echo "$config_conf" | egrep '^temperature_switch=' | sed -n 's/temperature_switch=//g;$p')"
temperature_switch_stop="$(echo "$config_conf" | egrep '^temperature_switch_stop=' | sed -n 's/temperature_switch_stop=//g;$p')"
temperature_switch_start="$(echo "$config_conf" | egrep '^temperature_switch_start=' | sed -n 's/temperature_switch_start=//g;$p')"

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
qsc_debug_step 5

if [ ! -n "$battery_level" ]; then
	for sysfs_cap in /sys/class/power_supply/battery/capacity /sys/class/power_supply/bms/capacity /sys/class/power_supply/battery/soc; do
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
	for sysfs_temp in /sys/class/power_supply/battery/temp /sys/class/power_supply/bms/temp /sys/class/power_supply/battery/batt_temp; do
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
	qsc_clear_active_switch
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

qsc_charge_full() {
	if [ "$charge_full" = "1" -a "$battery_level" = "100" -a "$power_stop" = "100" ]; then
		now_current="$(qsc_safe_cat /sys/class/power_supply/battery/current_now)"
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
# 必须同时「插电」且 status 为充电中(2)/已满(5)
# 仅凭 usb/online 会在停充后仍判为供电，导致每轮全量重写开关，小米上易与系统互抢闪充
if [ "$battery_status" = "2" -o "$battery_status" = "5" ]; then
	battery_status_data=1
fi

if [ -n "$battery_powered" -a "$battery_status_data" = "1" ]; then
	if [ -f "$LOG_FILE" ]; then
		log_n="$(cat "$LOG_FILE" | wc -l)"
		if [ "$log_n" -gt "80" ]; then
			sed -i '1,10d' "$LOG_FILE"
		fi
	fi
	if [ "$temperature_switch" = "1" ]; then
		if [ "$temperature_switch_stop" -gt "$temperature_switch_start" -a "$temperature" -ge "$temperature_switch_stop" ]; then
			touch "$DATADIR/temp_switch"
			cpu_log=1
		fi
	fi
	if [ "$power_stop" -gt "$power_start" -a "$battery_level" -ge "$power_stop" ]; then
		qsc_charge_full
		if [ "$full_log" = "0" ]; then
			switch_stop_mode=1
			battery_stop_reason=1
		fi
	fi
	if [ "$switch_stop_mode" = "1" -o "$cpu_log" = "1" ]; then
		first_stop=0
		if [ ! -f "$DATADIR/power_switch" ]; then
			first_stop=1
		fi
		if [ "$cpu_log" = "0" -a "$charge_full" != "1" -a "$first_stop" = "1" ]; then
			power_stop_time="$(echo "$config_conf" | egrep '^power_stop_time=' | sed -n 's/power_stop_time=//g;$p')"
			power_stop_time="$(qsc_clamp_int "$power_stop_time" 1 120 3)"
			if [ "$power_stop_time" -gt "0" ]; then
				qsc_log debug "电量$battery_level 延时功能 继续充电$power_stop_time秒 倒计时中"
				sleep "$power_stop_time"
			fi
		fi
		sleep 3
		# 首次全量探测；之后只重申已生效单节点（防小米多节点互抢 / 魅族息屏回充）
		if [ "$first_stop" = "1" ]; then
			qsc_power_stop
		else
			qsc_reaffirm_active_stop || qsc_power_stop
		fi
		if [ "$stop_ok" = "1" ]; then
			touch "$DATADIR/power_switch"
			qsc_stop_wakelock_acquire
			if [ "$battery_stop_reason" = "1" ]; then
				touch "$DATADIR/battery_switch"
			fi
			if [ "$first_stop" = "1" -a "$log_log" = "1" ]; then
				if [ "$cpu_log" = "1" ]; then
					qsc_log info "电量$battery_level 触发开关温控：停止充电 温度$temperature [$stop_nodes]"
				else
					qsc_log info "电量$battery_level 停止充电 [$stop_nodes]"
				fi
			fi
		elif [ "$first_stop" = "1" ]; then
			if [ ! -f "$DATADIR/no_node_logged" ]; then
				qsc_log error "电量$battery_level 未找到有效充电控制节点！请插电后执行 bin/test_switch.sh，或 Action 音量下生成诊断报告"
				touch "$DATADIR/no_node_logged"
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
fi

if [ -f "$DATADIR/power_switch" ] && [ "$off_qsc" != "1" ]; then
	temp_ready=1
	battery_ready=1
	if [ -f "$DATADIR/temp_switch" ]; then
		if [ "$temperature_switch" = "1" -a -n "$temperature_switch_start" -a "$temperature" -gt "$temperature_switch_start" ]; then
			temp_ready=0
		else
			cpu_log2=1
		fi
	fi
	if [ -f "$DATADIR/battery_switch" ]; then
		if [ "$power_stop" -le "100" -a "$power_stop" -gt "$power_start" -a "$battery_level" -gt "$power_start" ]; then
			battery_ready=0
		fi
	elif [ "$power_stop" -le "100" -a "$power_stop" -gt "$power_start" -a "$battery_level" -gt "$power_start" ]; then
		# 无原因标记的旧状态保守按电量停充处理，避免升级后在高电量误恢复
		battery_ready=0
	fi
	if [ "$temp_ready" = "1" -a "$battery_ready" = "1" ]; then
		sleep 3
		qsc_power_start
		if [ "$start_ok" = "1" ]; then
			rm -f "$DATADIR/power_switch" "$DATADIR/temp_switch" "$DATADIR/battery_switch"
			qsc_clear_active_switch
			qsc_stop_wakelock_release
		fi
		if [ "$log_log2" = "1" ]; then
			if [ "$cpu_log2" = "1" ]; then
				qsc_log info "电量$battery_level 触发开关温控：恢复充电 温度$temperature [$start_node <- $start_val]"
			else
				qsc_log info "电量$battery_level 恢复充电 [$start_node <- $start_val]"
			fi
		fi
	fi
fi

# 供电开关未停充时，若已安装电流控制组件则应用策略（兼容模式跳过，避免与其它限流模块抢写）
# 同样要求 status=充电中，避免停充后仍写电流节点与小米充电服务互抢
Compatibility_mode="$(echo "$config_conf" | egrep '^Compatibility_mode=' | sed -n 's/Compatibility_mode=//g;$p')"
[ -n "$Compatibility_mode" ] || Compatibility_mode=0
if [ -n "$battery_powered" ] && [ "$battery_status_data" = "1" ] && [ ! -f "$DATADIR/power_switch" ] && [ "$off_qsc" != "1" ]; then
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
elif [ ! -n "$battery_powered" ] || [ "$battery_status_data" != "1" ]; then
	rm -f "$DATADIR/current_mode_tag"
	rm -f "$DATADIR/current_reaffirm_ts" "$DATADIR/current_drift_streak"
	if type qsc_bypass_hw_off >/dev/null 2>&1; then
		qsc_bypass_hw_off
	fi
fi

qsc_refresh_module_description

qsc_debug_step 9
#version=20260805
# ##
