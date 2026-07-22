#!/system/bin/sh
. "${0%/*}/common.sh"

echo "$(date +%F_%T) qsc_switch.sh 被调用" >> "$DATADIR/startup.log"
_debug_step() { echo "$(date +%F_%T) step$1" >> "$DATADIR/debug.log"; }
_safe_cat() {
	cat "$1" > "$DATADIR/.safe_tmp" 2>/dev/null &
	local _pid=$!
	local _i
	for _i in 1 2; do
		if [ ! -d "/proc/$_pid" ]; then break; fi
		sleep 1
	done
	kill $_pid 2>/dev/null
	cat "$DATADIR/.safe_tmp" 2>/dev/null
}
_normalize_temperature() {
	local raw digits normalized
	raw="$(echo "$1" | tr -d ' \r\n')"
	case "$raw" in ""|"-"|*[!0-9-]*) return 1 ;; esac
	digits="${raw#-}"
	case "$digits" in ""|*[!0-9]*) return 1 ;; esac
	if [ "$digits" -ge 10000 ]; then
		normalized=$((raw / 1000))
	elif [ "$digits" -ge 1000 ]; then
		normalized=$((raw / 100))
	elif [ "$digits" -ge 100 ]; then
		normalized=$((raw / 10))
	else
		normalized="$raw"
	fi
	[ "$normalized" -ge -20 -a "$normalized" -le 100 ] || return 1
	echo "$normalized"
}
_debug_step 1
config_conf="$(cat "$CONF" | egrep -v '^#')"
_debug_step 2
dumpsys battery > "$DATADIR/.dumpsys_tmp" 2>/dev/null &
dumpsys_pid=$!
for wait_i in 1 2 3 4 5; do
	if [ ! -d "/proc/$dumpsys_pid" ]; then break; fi
	sleep 1
done
kill $dumpsys_pid 2>/dev/null
dumpsys_battery="$(cat "$DATADIR/.dumpsys_tmp" 2>/dev/null)"
_debug_step 3
rm -f "$DATADIR/.dumpsys_tmp"
battery_level="$(echo "$dumpsys_battery" | egrep '^[ ]*level: ' | sed -n 's/.*level: //g;$p')"
battery_powered="$(echo "$dumpsys_battery" | egrep 'powered: true')"
battery_status="$(echo "$dumpsys_battery" | egrep 'status: ' | sed -n 's/.*status: //g;$p')"
_debug_step 4
if [ ! -n "$battery_powered" ] || [ ! -n "$battery_status" ]; then
	sysfs_status="$(_safe_cat /sys/class/power_supply/battery/status)"
	if [ -n "$sysfs_status" ]; then
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
		if [ -f "$usb_online" ] && [ "$(_safe_cat "$usb_online")" = "1" ]; then
			battery_powered="powered: true"
			battery_status="${battery_status:-2}"
			break
		fi
	done
fi
charge_full="$(echo "$config_conf" | egrep '^charge_full=' | sed -n 's/charge_full=//g;$p')"
power_reset="$(echo "$config_conf" | egrep '^power_reset=' | sed -n 's/power_reset=//g;$p')"
Shut_down="$(echo "$config_conf" | egrep '^Shut_down=' | sed -n 's/Shut_down=//g;$p')"
temperature_raw="$(echo "$dumpsys_battery" | egrep 'temperature: ' | sed -n 's/.*temperature: //g;$p')"
temperature="$(_normalize_temperature "$temperature_raw")"
power_stop="$(echo "$config_conf" | egrep '^power_stop=' | sed -n 's/power_stop=//g;$p')"
power_start="$(echo "$config_conf" | egrep '^power_start=' | sed -n 's/power_start=//g;$p')"
temperature_switch="$(echo "$config_conf" | egrep '^temperature_switch=' | sed -n 's/temperature_switch=//g;$p')"
temperature_switch_stop="$(echo "$config_conf" | egrep '^temperature_switch_stop=' | sed -n 's/temperature_switch_stop=//g;$p')"
temperature_switch_start="$(echo "$config_conf" | egrep '^temperature_switch_start=' | sed -n 's/temperature_switch_start=//g;$p')"
off_qsc=0
_debug_step 5
if [ ! -n "$battery_level" ]; then
	for sysfs_cap in /sys/class/power_supply/battery/capacity /sys/class/power_supply/bms/capacity /sys/class/power_supply/battery/soc; do
		if [ -f "$sysfs_cap" ] && [ -r "$sysfs_cap" ]; then
			battery_level="$(_safe_cat "$sysfs_cap")"
			if [ -n "$battery_level" ]; then break; fi
		fi
	done
fi
_debug_step 6
if [ ! -n "$battery_level" ]; then
	if [ ! -f "$DATADIR/no_battery_logged" ]; then
		echo "$(date +%F_%T) 无法获取电池电量！dumpsys 超时且 sysfs 也读取失败" >> "$LOG_FILE"
		touch "$DATADIR/no_battery_logged"
	fi
	exit 0
fi
if [ ! -n "$temperature" ]; then
	for sysfs_temp in /sys/class/power_supply/battery/temp /sys/class/power_supply/bms/temp /sys/class/power_supply/battery/batt_temp; do
		if [ -f "$sysfs_temp" ] && [ -r "$sysfs_temp" ]; then
			temperature_raw="$(_safe_cat "$sysfs_temp")"
			temperature="$(_normalize_temperature "$temperature_raw")"
			if [ -n "$temperature" ]; then break; fi
		fi
	done
fi
_debug_step 7
if [ ! -n "$temperature" ]; then
	if [ ! -f "$DATADIR/no_temp_logged" ]; then
		echo "$(date +%F_%T) 无法获取电池温度！dumpsys 超时且 sysfs 也读取失败" >> "$LOG_FILE"
		touch "$DATADIR/no_temp_logged"
	fi
	exit 0
fi
if [ -f "$OFF_FLAG" -o -f "$MODDIR/disable" ]; then
	off_qsc=1
	power_stop="110"
	power_start="105"
	temperature_switch="0"
	if [ ! -f "$DATADIR/off_d" ]; then
		sed -i 's/\[.*\]/\[ 模块已关闭 \]/g' "$MODDIR/module.prop"
		touch "$DATADIR/off_d"
		rm -f "$DATADIR/now_c"
		rm -f "$DATADIR/power_on"
		rm -f "$DATADIR/power_off"
	fi
else
	if [ -f "$DATADIR/off_d" ]; then
		rm -f "$DATADIR/off_d"
	fi
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
		echo "$(date +%F_%T) 缺少列表文件，正在创建，请稍等" > "$LOG_FILE"
		exit 0
	else
		echo "$(date +%F_%T) list_switch.sh文件不存在，请重新安装模块重启" > "$LOG_FILE"
		exit 0
	fi
fi
switch_list="$(cat "$LIST_SWITCH")"
switch_list="$switch_list /sys/class/power_supply/battery/batt_slate_mode,start=0,stop=1 /sys/class/power_supply/battery/store_mode,start=0,stop=1 /sys/class/power_supply/battery/input_suspend,start=0,stop=1 /sys/class/power_supply/battery/charging_enabled,start=1,stop=0 /sys/class/power_supply/battery/charge_disable,start=0,stop=1 /sys/class/power_supply/battery/disable_charging,start=0,stop=1 /sys/class/power_supply/battery/stop_charging,start=0,stop=1 /sys/class/power_supply/battery/charge_enabled,start=1,stop=0 /sys/class/power_supply/charger/charge_disable,start=0,stop=1 /sys/class/power_supply/bms/charge_disable,start=0,stop=1 /sys/class/power_supply/bms/charging_enabled,start=1,stop=0 /sys/class/power_supply/bms/charge_enabled,start=1,stop=0 /sys/class/power_supply/mi_chg/charge_disable,start=0,stop=1 /sys/class/power_supply/mi_chg/charging_enabled,start=1,stop=0 /sys/class/qcom-battery/charging_enabled,start=1,stop=0 /sys/class/qcom-battery/charge_disable,start=0,stop=1 /sys/class/qcom-battery/input_suspend,start=0,stop=1 /sys/class/qcom-battery/battery_charging_enabled,start=1,stop=0 /sys/class/power_supply/idt/pin_enabled,start=1,stop=0 /sys/kernel/debug/google_charger/chg_suspend,start=0,stop=1 /sys/kernel/debug/google_charger/chg_mode,start=1,stop=0 /proc/driver/charger_limit_enable,start=0,stop=1 /proc/driver/charger_limit,start=100,stop=1 /proc/mtk_battery_cmd/current_cmd,start=0_0,stop=0_1 /proc/mtk_battery_cmd/en_power_path,start=1,stop=0 /sys/class/power_supply/battery/constant_charge_current_max,start=3000000,stop=0 /sys/class/power_supply/battery/current_max,start=3000000,stop=0 /sys/class/power_supply/battery/input_current_max,start=3000000,stop=0 /sys/class/power_supply/battery/charge_current,start=3000000,stop=0 /sys/class/power_supply/battery/fast_charge_current_max,start=3000000,stop=0 /sys/class/power_supply/usb/input_suspend,start=0,stop=1 /sys/class/power_supply/qc_usb/input_suspend,start=0,stop=1 /sys/class/power_supply/dc/input_suspend,start=0,stop=1 /sys/class/power_supply/battery/charge_control_end_threshold,start=100,stop=0 /sys/class/power_supply/battery/charge_type,start=Fast,stop=None /sys/class/power_supply/battery/batt_charging_enabled,start=1,stop=0 /sys/class/power_supply/battery/force_disable_charging,start=0,stop=1 /sys/class/power_supply/battery/charge_control_enabled,start=1,stop=0 /sys/class/power_supply/battery/mi_charge_enable,start=1,stop=0 /sys/class/power_supply/pc_port/input_suspend,start=0,stop=1 /sys/class/power_supply/wireless/input_suspend,start=0,stop=1 /sys/devices/platform/soc/soc:mca_business_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/soc:mca_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/soc@0:mca_business_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/soc@0:mca_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/mca_business_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/mca_charger/handle_state,start=0,stop=1 /sys/class/power_supply/mca-charger/handle_state,start=0,stop=1 /sys/class/power_supply/mca_charger/handle_state,start=0,stop=1 /sys/class/power_supply/mca-battery/handle_state,start=0,stop=1 /sys/class/power_supply/mca_battery/handle_state,start=0,stop=1 /sys/devices/platform/soc/soc:mca_business_charger/stop_handle_charge,start=0,stop=1"
# K90U / 骁龙8至尊版 MCA：系统可能周期性改回 handle_state，需 chmod 后写入并在停充期间持续重申。
_MCA_HANDLE_PATHS="/sys/devices/platform/soc/soc:mca_business_charger/handle_state /sys/devices/platform/soc/soc:mca_charger/handle_state /sys/devices/platform/soc/soc@0:mca_business_charger/handle_state /sys/devices/platform/soc/soc@0:mca_charger/handle_state /sys/devices/platform/soc/mca_business_charger/handle_state /sys/devices/platform/soc/mca_charger/handle_state /sys/class/power_supply/mca-charger/handle_state /sys/class/power_supply/mca_charger/handle_state /sys/class/power_supply/mca-battery/handle_state /sys/class/power_supply/mca_battery/handle_state"
_qsc_write_node() {
	local node="$1"
	local val="$2"
	chmod 0644 "$node" 2>/dev/null
	echo "$val" > "$node" 2>/dev/null
}
_qsc_mca_write() {
	local val="$1"
	local label="$2"
	local mca_path
	for mca_path in $_MCA_HANDLE_PATHS; do
		if [ -f "$mca_path" ]; then
			_qsc_write_node "$mca_path" "$val"
			if [ "$label" = "stop" ]; then
				stop_nodes="$mca_path=$val (MCA)"
				log_log=1
				stop_ok=1
			else
				start_node="$mca_path"
				start_val="$val"
				log_log2=1
				start_ok=1
			fi
			return 0
		fi
	done
	return 1
}
qsc_power_stop() {
	stop_ok=0
	stop_nodes=""
	if _qsc_mca_write 1 stop; then
		return
	fi
	for i in $switch_list ; do
		power_switch_route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
		if [ -f "$power_switch_route" ]; then
			power_switch_stop="$(echo "$i" | sed -n 's/.*,stop=//g;s/_/ /g;$p')"
			_qsc_write_node "$power_switch_route" "$power_switch_stop"
			stop_nodes="$stop_nodes $power_switch_route=$power_switch_stop"
			log_log=1
			stop_ok=1
		fi
	done
}
qsc_power_start() {
	start_ok=0
	start_node=""
	start_val=""
	if _qsc_mca_write 0 start; then
		return
	fi
	for i in $switch_list ; do
		power_switch_route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
		if [ -f "$power_switch_route" ]; then
			power_switch_start="$(echo "$i" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
			_qsc_write_node "$power_switch_route" "$power_switch_start"
			start_node="$power_switch_route"
			start_val="$power_switch_start"
			log_log2=1
			start_ok=1
		fi
	done
}
qsc_charge_full() {
	if [ "$charge_full" = "1" -a "$battery_level" = "100" -a "$power_stop" = "100" ]; then
		now_current="$(_safe_cat /sys/class/power_supply/battery/current_now)"
		if [ "$battery_status" = "5" ]; then
			rm -f "$DATADIR/now_c"
			echo "$(date +%F_%T) 电量$battery_level 触发充满再停功能 当前已充满" >> "$LOG_FILE"
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
					echo "$(date +%F_%T) 电量$battery_level 触发充满再停功能 当前电流$now_current" >> "$LOG_FILE"
				fi
			fi
		fi
	fi
}
qsc_power_reset() {
	sleep 2
	qsc_power_stop
	sleep 1
	qsc_power_start
}
_debug_step 8
if [ "$battery_status" = "2" -o "$battery_status" = "5" ]; then
	battery_status_data=1
fi
if [ -n "$battery_powered" ]; then
	if [ -f "$LOG_FILE" ]; then
		log_n="$(cat "$LOG_FILE" | wc -l)"
		if [ "$log_n" -gt "30" ]; then
			sed -i '1,5d' "$LOG_FILE"
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
			if [ "$power_stop_time" -gt "0" ]; then
				echo "$(date +%F_%T) 电量$battery_level 延时功能 继续充电$power_stop_time秒 倒计时中" >> "$LOG_FILE"
				sleep "$power_stop_time"
			fi
		fi
		sleep 3
		# K90U/MCA 等机型会改回停充节点，条件仍满足时每轮重申
		qsc_power_stop
		if [ "$stop_ok" = "1" ]; then
			touch "$DATADIR/power_switch"
			if [ "$battery_stop_reason" = "1" ]; then
				touch "$DATADIR/battery_switch"
			fi
			if [ "$first_stop" = "1" -a "$log_log" = "1" ]; then
				if [ "$cpu_log" = "1" ]; then
					echo "$(date +%F_%T) 电量$battery_level 触发开关温控：停止充电 温度$temperature [$stop_nodes]" >> "$LOG_FILE"
				else
					echo "$(date +%F_%T) 电量$battery_level 停止充电 [$stop_nodes]" >> "$LOG_FILE"
				fi
			fi
		elif [ "$first_stop" = "1" ]; then
			if [ ! -f "$DATADIR/no_node_logged" ]; then
				echo "$(date +%F_%T) 电量$battery_level 未找到有效充电控制节点！请运行 bin/diagnose.sh 生成诊断报告发给开发者" >> "$LOG_FILE"
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
		sed -i 's/\[.*\]/\[ 充电中 \]/g' "$MODDIR/module.prop"
		rm -f "$DATADIR/power_off"
		touch "$DATADIR/power_on"
		if [ "$power_reset" = "1" -a "$reset_log" = "1" ]; then
			qsc_power_reset
			echo "$(date +%F_%T) 电量$battery_level 触发自动拔插功能" >> "$LOG_FILE"
		fi
	fi
else
	if [ ! -f "$DATADIR/power_off" -a "$off_qsc" != "1" ]; then
		sed -i 's/\[.*\]/\[ 未充电 \]/g' "$MODDIR/module.prop"
		rm -f "$DATADIR/now_c"
		rm -f "$DATADIR/power_on"
		touch "$DATADIR/power_off"
	fi
fi
if [ -f "$DATADIR/power_switch" ]; then
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
		# 无原因标记的旧状态保守按电量停充处理，避免升级后在高电量误恢复。
		battery_ready=0
	fi
	if [ "$temp_ready" = "1" -a "$battery_ready" = "1" ]; then
		sleep 3
		qsc_power_start
		if [ "$start_ok" = "1" ]; then
			rm -f "$DATADIR/power_switch"
			rm -f "$DATADIR/temp_switch"
			rm -f "$DATADIR/battery_switch"
		fi
		if [ "$log_log2" = "1" ]; then
			if [ "$cpu_log2" = "1" ]; then
				echo "$(date +%F_%T) 电量$battery_level 触发开关温控：恢复充电 温度$temperature [$start_node <- $start_val]" >> "$LOG_FILE"
			else
				echo "$(date +%F_%T) 电量$battery_level 恢复充电 [$start_node <- $start_val]" >> "$LOG_FILE"
			fi
		fi
	fi
fi
_debug_step 9
#version=20260722.2
# ##
