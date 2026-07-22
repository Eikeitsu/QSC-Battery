#!/system/bin/sh
# 充电节点写入：通用 fallback 列表 + MCA 优先 + 停充/恢复

# 各机型常见节点兜底（与 list_switch 扫描互补；运行时仍以文件是否存在为准）
QSC_FALLBACK_SWITCHES="\
/sys/class/power_supply/battery/batt_slate_mode,start=0,stop=1 \
/sys/class/power_supply/battery/store_mode,start=0,stop=1 \
/sys/class/power_supply/battery/input_suspend,start=0,stop=1 \
/sys/class/power_supply/battery/charging_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/charge_disable,start=0,stop=1 \
/sys/class/power_supply/battery/disable_charging,start=0,stop=1 \
/sys/class/power_supply/battery/stop_charging,start=0,stop=1 \
/sys/class/power_supply/battery/charge_enabled,start=1,stop=0 \
/sys/class/power_supply/charger/charge_disable,start=0,stop=1 \
/sys/class/power_supply/bms/charge_disable,start=0,stop=1 \
/sys/class/power_supply/bms/charging_enabled,start=1,stop=0 \
/sys/class/power_supply/bms/charge_enabled,start=1,stop=0 \
/sys/class/power_supply/mi_chg/charge_disable,start=0,stop=1 \
/sys/class/power_supply/mi_chg/charging_enabled,start=1,stop=0 \
/sys/class/qcom-battery/charging_enabled,start=1,stop=0 \
/sys/class/qcom-battery/charge_disable,start=0,stop=1 \
/sys/class/qcom-battery/input_suspend,start=0,stop=1 \
/sys/class/qcom-battery/battery_charging_enabled,start=1,stop=0 \
/sys/class/power_supply/idt/pin_enabled,start=1,stop=0 \
/sys/kernel/debug/google_charger/chg_suspend,start=0,stop=1 \
/sys/kernel/debug/google_charger/chg_mode,start=1,stop=0 \
/proc/driver/charger_limit_enable,start=0,stop=1 \
/proc/driver/charger_limit,start=100,stop=1 \
/proc/mtk_battery_cmd/current_cmd,start=0_0,stop=0_1 \
/proc/mtk_battery_cmd/en_power_path,start=1,stop=0 \
/sys/class/power_supply/battery/constant_charge_current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/input_current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/charge_current,start=3000000,stop=0 \
/sys/class/power_supply/battery/fast_charge_current_max,start=3000000,stop=0 \
/sys/class/power_supply/usb/input_suspend,start=0,stop=1 \
/sys/class/power_supply/qc_usb/input_suspend,start=0,stop=1 \
/sys/class/power_supply/dc/input_suspend,start=0,stop=1 \
/sys/class/power_supply/battery/charge_control_end_threshold,start=100,stop=0 \
/sys/class/power_supply/battery/charge_type,start=Fast,stop=None \
/sys/class/power_supply/battery/batt_charging_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/force_disable_charging,start=0,stop=1 \
/sys/class/power_supply/battery/charge_control_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/mi_charge_enable,start=1,stop=0 \
/sys/class/power_supply/pc_port/input_suspend,start=0,stop=1 \
/sys/class/power_supply/wireless/input_suspend,start=0,stop=1"

qsc_write_node() {
	local node="$1"
	local val="$2"
	chmod 0644 "$node" 2>/dev/null
	echo "$val" > "$node" 2>/dev/null
}

# 组装 switch_list：扫描结果 + 兜底 +（若有）本机 MCA
qsc_build_switch_list() {
	switch_list="$(cat "$LIST_SWITCH" 2>/dev/null)"
	switch_list="$switch_list $QSC_FALLBACK_SWITCHES"
	qsc_load_device_profile
	if [ "$QSC_MCA" = "1" ] && [ -n "$QSC_MCA_PATH" ]; then
		switch_list="$switch_list ${QSC_MCA_PATH},start=${QSC_MCA_START},stop=${QSC_MCA_STOP}"
	fi
}

qsc_mca_write() {
	local val="$1"
	local label="$2"
	[ "$QSC_MCA" = "1" ] || return 1
	[ -n "$QSC_MCA_PATH" ] && [ -f "$QSC_MCA_PATH" ] || return 1
	qsc_write_node "$QSC_MCA_PATH" "$val"
	if [ "$label" = "stop" ]; then
		stop_nodes="$QSC_MCA_PATH=$val (MCA)"
		log_log=1
		stop_ok=1
	else
		start_node="$QSC_MCA_PATH"
		start_val="$val"
		log_log2=1
		start_ok=1
	fi
	return 0
}

qsc_power_stop() {
	local i power_switch_route power_switch_stop
	stop_ok=0
	stop_nodes=""
	if qsc_mca_write "$QSC_MCA_STOP" stop; then
		return
	fi
	for i in $switch_list; do
		power_switch_route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
		if [ -f "$power_switch_route" ]; then
			power_switch_stop="$(echo "$i" | sed -n 's/.*,stop=//g;s/_/ /g;$p')"
			qsc_write_node "$power_switch_route" "$power_switch_stop"
			stop_nodes="$stop_nodes $power_switch_route=$power_switch_stop"
			log_log=1
			stop_ok=1
		fi
	done
}

qsc_power_start() {
	local i power_switch_route power_switch_start
	start_ok=0
	start_node=""
	start_val=""
	if qsc_mca_write "$QSC_MCA_START" start; then
		return
	fi
	for i in $switch_list; do
		power_switch_route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
		if [ -f "$power_switch_route" ]; then
			power_switch_start="$(echo "$i" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
			qsc_write_node "$power_switch_route" "$power_switch_start"
			start_node="$power_switch_route"
			start_val="$power_switch_start"
			log_log2=1
			start_ok=1
		fi
	done
}

qsc_power_reset() {
	sleep 2
	qsc_power_stop
	sleep 1
	qsc_power_start
}

# 卸载时按列表恢复 start 值
qsc_restore_switches_from_list() {
	local i route start_val
	[ -f "$LIST_SWITCH" ] || return 1
	for i in $(cat "$LIST_SWITCH"); do
		route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
		if [ -f "$route" ]; then
			start_val="$(echo "$i" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
			echo "$start_val" > "$route" 2>/dev/null
		fi
	done
}

qsc_restore_mca_charge() {
	qsc_load_device_profile 2>/dev/null || true
	if [ "$QSC_MCA" = "1" ] && [ -n "$QSC_MCA_PATH" ] && [ -f "$QSC_MCA_PATH" ]; then
		chmod 0644 "$QSC_MCA_PATH" 2>/dev/null
		echo "${QSC_MCA_START:-0}" > "$QSC_MCA_PATH" 2>/dev/null
		return 0
	fi
	local mca
	for mca in $QSC_MCA_CANDIDATES; do
		if [ -f "$mca" ]; then
			chmod 0644 "$mca" 2>/dev/null
			echo "0" > "$mca" 2>/dev/null
		fi
	done
}
