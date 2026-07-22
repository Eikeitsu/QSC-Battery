#!/system/bin/sh
# 停充主循环：读配置/电量 → 判定 → 调用 lib/charge 写节点
. "${0%/*}/common.sh"

echo "$(date +%F_%T) qsc_switch.sh 被调用" >> "$DATADIR/startup.log"
qsc_debug_step 1

config_conf="$(cat "$CONF" | egrep -v '^#')"
qsc_debug_step 2

dumpsys battery > "$DATADIR/.dumpsys_tmp" 2>/dev/null &
dumpsys_pid=$!
for wait_i in 1 2 3 4 5; do
	if [ ! -d "/proc/$dumpsys_pid" ]; then break; fi
	sleep 1
done
kill $dumpsys_pid 2>/dev/null
dumpsys_battery="$(cat "$DATADIR/.dumpsys_tmp" 2>/dev/null)"
qsc_debug_step 3
rm -f "$DATADIR/.dumpsys_tmp"

battery_level="$(echo "$dumpsys_battery" | egrep '^[ ]*level: ' | sed -n 's/.*level: //g;$p')"
battery_powered="$(echo "$dumpsys_battery" | egrep 'powered: true')"
battery_status="$(echo "$dumpsys_battery" | egrep 'status: ' | sed -n 's/.*status: //g;$p')"
qsc_debug_step 4

if [ ! -n "$battery_powered" ] || [ ! -n "$battery_status" ]; then
	sysfs_status="$(qsc_safe_cat /sys/class/power_supply/battery/status)"
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
		if [ -f "$usb_online" ] && [ "$(qsc_safe_cat "$usb_online")" = "1" ]; then
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
temperature="$(qsc_normalize_temperature "$temperature_raw")"
power_stop="$(echo "$config_conf" | egrep '^power_stop=' | sed -n 's/power_stop=//g;$p')"
power_start="$(echo "$config_conf" | egrep '^power_start=' | sed -n 's/power_start=//g;$p')"
temperature_switch="$(echo "$config_conf" | egrep '^temperature_switch=' | sed -n 's/temperature_switch=//g;$p')"
temperature_switch_stop="$(echo "$config_conf" | egrep '^temperature_switch_stop=' | sed -n 's/temperature_switch_stop=//g;$p')"
temperature_switch_start="$(echo "$config_conf" | egrep '^temperature_switch_start=' | sed -n 's/temperature_switch_start=//g;$p')"
off_qsc=0
qsc_debug_step 5

if [ ! -n "$battery_level" ]; then
	for sysfs_cap in /sys/class/power_supply/battery/capacity /sys/class/power_supply/bms/capacity /sys/class/power_supply/battery/soc; do
		if [ -f "$sysfs_cap" ] && [ -r "$sysfs_cap" ]; then
			battery_level="$(qsc_safe_cat "$sysfs_cap")"
			if [ -n "$battery_level" ]; then break; fi
		fi
	done
fi
qsc_debug_step 6
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
			temperature_raw="$(qsc_safe_cat "$sysfs_temp")"
			temperature="$(qsc_normalize_temperature "$temperature_raw")"
			if [ -n "$temperature" ]; then break; fi
		fi
	done
fi
qsc_debug_step 7
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
		rm -f "$DATADIR/now_c" "$DATADIR/power_on" "$DATADIR/power_off"
	fi
else
	rm -f "$DATADIR/off_d"
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
	fi
	echo "$(date +%F_%T) list_switch.sh文件不存在，请重新安装模块重启" > "$LOG_FILE"
	exit 0
fi

qsc_build_switch_list

qsc_charge_full() {
	if [ "$charge_full" = "1" -a "$battery_level" = "100" -a "$power_stop" = "100" ]; then
		now_current="$(qsc_safe_cat /sys/class/power_supply/battery/current_now)"
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

qsc_debug_step 8
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
		# 条件仍满足时每轮重申；MCA 机型依赖此逻辑对抗系统改回
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
				echo "$(date +%F_%T) 电量$battery_level 未找到有效充电控制节点！请在模块 Action 运行 diagnose 或执行 bin/diagnose.sh" >> "$LOG_FILE"
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
		rm -f "$DATADIR/now_c" "$DATADIR/power_on"
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
		# 无原因标记的旧状态保守按电量停充处理，避免升级后在高电量误恢复
		battery_ready=0
	fi
	if [ "$temp_ready" = "1" -a "$battery_ready" = "1" ]; then
		sleep 3
		qsc_power_start
		if [ "$start_ok" = "1" ]; then
			rm -f "$DATADIR/power_switch" "$DATADIR/temp_switch" "$DATADIR/battery_switch"
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

qsc_debug_step 9
#version=20260723
# ##
