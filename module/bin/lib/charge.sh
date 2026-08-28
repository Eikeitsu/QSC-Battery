#!/system/bin/sh
# 充电节点写入：用户 power_switch + 通用 fallback + MCA / preferred 优先

# 各机型常见停充节点；运行时仍以文件是否存在为准。值里空格用 _ 表示（写入前还原）。
# 真正供电开关优先；电流伪开关 / 输入口 suspend 放在 QSC_LAST_RESORT_SWITCHES。
QSC_FALLBACK_SWITCHES="\
/sys/class/power_supply/battery/charge_charger_state,start=1,stop=0 \
/sys/class/power_supply/battery/connect_disable,start=0,stop=1 \
/sys/class/power_supply/battery/batt_slate_mode,start=0,stop=1 \
/sys/class/power_supply/battery/store_mode,start=0,stop=1 \
/sys/class/power_supply/battery/input_suspend,start=0,stop=1 \
/sys/class/power_supply/battery/battery_input_suspend,start=0,stop=1 \
/sys/class/power_supply/battery/charging_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/battery_charging_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/batt_charging_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/charge_disable,start=0,stop=1 \
/sys/class/power_supply/battery/disable_charging,start=0,stop=1 \
/sys/class/power_supply/battery/stop_charging,start=0,stop=1 \
/sys/class/power_supply/battery/charge_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/op_disable_charge,start=0,stop=1 \
/sys/class/power_supply/battery/device/Charging_Enable,start=1,stop=0 \
/sys/class/power_supply/battery/ChargerEnable,start=1,stop=0 \
/sys/class/power_supply/battery/force_disable_charging,start=0,stop=1 \
/sys/class/power_supply/battery/charge_control_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/mi_charge_enable,start=1,stop=0 \
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
/sys/class/qcom-battery/charging_suspend_battery,start=0,stop=1 \
/sys/class/asuslib/charger_limit_en,start=0,stop=1 \
/sys/class/asuslib/charging_suspend_en,start=0,stop=1 \
/sys/class/hw_power/charger/charge_data/enable_charger,start=1,stop=0 \
/sys/class/power_supply/idt/pin_enabled,start=1,stop=0 \
/sys/devices/platform/huawei_charger/enable_charger,start=1,stop=0 \
/sys/devices/platform/lge-unified-nodes/charging_enable,start=1,stop=0 \
/sys/devices/platform/lge-unified-nodes/charging_completed,start=0,stop=1 \
/sys/devices/platform/mt-battery/disable_charger,start=0,stop=1 \
/sys/devices/platform/battery/ChargerEnable,start=1,stop=0 \
/sys/devices/platform/soc/soc:google,charger/charge_disable,start=0,stop=1 \
/sys/devices/platform/charger/bypass_charger,start=0,stop=1 \
/sys/devices/platform/soc/soc:qcom,pmic_glink/soc:qcom,pmic_glink:qcom,battery_charger/force_charger_suspend,start=0,stop=1 \
/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable,start=1,stop=0 \
/sys/kernel/debug/google_charger/chg_suspend,start=0,stop=1 \
/sys/kernel/debug/google_charger/input_suspend,start=0,stop=1 \
/sys/kernel/debug/google_charger/chg_mode,start=1,stop=0 \
/sys/kernel/nubia_charge/charger_bypass,start=off,stop=on \
/sys/module/qpnp_adaptive_charge/parameters/blocking,start=0,stop=1 \
/proc/driver/charger_limit_enable,start=0,stop=1 \
/proc/driver/charger_limit,start=100,stop=1 \
/proc/mtk_battery_cmd/current_cmd,start=0_0,stop=0_1 \
/proc/mtk_battery_cmd/en_power_path,start=1,stop=0 \
/sys/class/power_supply/ac/device/power_supply/usb/power_switch,start=1,stop=0 \
/sys/devices/platform/soc/soc:mca_business_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/soc:mca_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/soc@0:mca_business_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/soc@0:mca_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/mca_business_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/mca_charger/handle_state,start=0,stop=1 \
/sys/class/power_supply/mca-charger/handle_state,start=0,stop=1 \
/sys/class/power_supply/mca_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/soc:mca_business_charger/stop_handle_charge,start=0,stop=1 \
/sys/devices/platform/soc/soc:mca_charger/stop_handle_charge,start=0,stop=1"

# 仅当常规开关全部写失败时才试：电流墙 / 端口 suspend（易与快充协商打架，故置后）
QSC_LAST_RESORT_SWITCHES="\
/sys/class/power_supply/battery/constant_charge_current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/input_current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/fast_charge_current_max,start=3000000,stop=0 \
/sys/class/power_supply/usb/input_suspend,start=0,stop=1 \
/sys/class/power_supply/qc_usb/input_suspend,start=0,stop=1 \
/sys/class/power_supply/dc/input_suspend,start=0,stop=1 \
/sys/class/power_supply/wireless/input_suspend,start=0,stop=1 \
/sys/class/power_supply/pc_port/input_suspend,start=0,stop=1 \
/sys/class/power_supply/battery/charge_type,start=Fast,stop=None"

QSC_USER_SWITCHES=""

qsc_write_node() {
	local node="$1"
	local val="$2"
	local key
	chmod 0644 "$node" 2>/dev/null
	if ! echo "$val" > "$node" 2>/dev/null; then
		key="$(echo "$node" | tr / _)"
		qsc_log_once "wn_$key" warn "写入节点失败 $node ← $val"
		return 1
	fi
	return 0
}

# MCA handle_state：直接 echo，避免 chmod 破坏权限（小米17/K90 实测要点）
qsc_mca_raw_echo() {
	local node="$1"
	local val="$2"
	[ -f "$node" ] || return 1
	echo "$val" > "$node" 2>/dev/null || return 1
	return 0
}

# 将一行配置规范为 path,start=X,stop=Y（兼容 [] 与 :: 空格写法）
qsc_normalize_power_switch_entry() {
	local raw="$1"
	local body path start stop
	raw="$(echo "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	[ -n "$raw" ] || return 1
	case "$raw" in
		\#*) return 1 ;;
	esac
	# power_switch=[...] 或 power_switch=...
	case "$raw" in
		power_switch=\[*\])
			body="$(echo "$raw" | sed 's/^power_switch=\[//;s/\]$//')"
			;;
		power_switch=*)
			body="$(echo "$raw" | sed 's/^power_switch=//')"
			;;
		*)
			body="$raw"
			;;
	esac
	body="$(echo "$body" | sed 's/::/_/g')"
	# 已是内部逗号格式
	case "$body" in
		*,start=*,stop=*)
			echo "$body"
			return 0
			;;
	esac
	path="$(echo "$body" | awk '{print $1}')"
	start="$(echo "$body" | sed -n 's/.*start=\([^[:space:]]*\).*/\1/p')"
	stop="$(echo "$body" | sed -n 's/.*stop=\([^[:space:]]*\).*/\1/p')"
	[ -n "$path" ] && [ -n "$start" ] && [ -n "$stop" ] || return 1
	echo "${path},start=${start},stop=${stop}"
}

# 读取 config.conf 中用户自定义供电开关（可多行）
qsc_load_user_switches() {
	local line entry
	QSC_USER_SWITCHES=""
	[ -f "$CONF" ] || return 0
	local n=0
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			power_switch=*)
				entry="$(qsc_normalize_power_switch_entry "$line")" || {
					qsc_log_once "psw_bad_$n" warn "忽略无效 power_switch 行"
					continue
				}
				QSC_USER_SWITCHES="$QSC_USER_SWITCHES $entry"
				n=$((n + 1))
				;;
		esac
	done <"$CONF"
	if [ "$n" -gt 0 ]; then
		qsc_log_once user_sw debug "已加载 ${n} 条自定义供电开关"
	fi
}

# 策略/温控类节点：不是可靠供电开关，自动扫描与盲写一律跳过（用户显式 power_switch 仍可用）
# night_charging / cool_mode / batt_protect
qsc_is_policy_switch_node() {
	case "$1" in
		*night_charging*|*cool_mode*|*batt_protect*|*smart_charging*|*adapter_cc_mode*|\
		*step_charging*|*restrict_chg*|*restricted_charging*|*charge_control_end*|\
		*charge_control_start*|*charge_control_limit*|*thermal_input*)
			return 0
			;;
	esac
	return 1
}

# 按列表写停充/恢复。
# stop + first/verify：逐个尝试；verify 时写入后检查是否真停充
qsc_write_switch_list() {
	local mode="$1"
	local list="$2"
	local first_only="${3:-}"
	local allow_policy="${4:-}"
	local i route val start_val
	for i in $list; do
		route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
		[ -f "$route" ] || continue
		if [ "$allow_policy" != "1" ] && qsc_is_policy_switch_node "$route"; then
			continue
		fi
		if [ "$mode" = "stop" ]; then
			val="$(echo "$i" | sed -n 's/.*,stop=//g;s/_/ /g;$p')"
			if qsc_write_node "$route" "$val"; then
				if [ "$first_only" = "verify" ]; then
					_vd="$(echo "$config_conf" | egrep '^switch_verify_sec=' | sed -n 's/switch_verify_sec=//g;$p')"
					_vd="$(qsc_clamp_int "${_vd:-1}" 0 5 1)"
					[ "$_vd" -gt 0 ] 2>/dev/null && sleep "$_vd"
					if ! qsc_charge_looks_stopped; then
						start_val="$(echo "$i" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
						qsc_write_node "$route" "$start_val" 2>/dev/null || true
						qsc_log_once "sw_ineff_${route##*/}" warn "节点写入成功但未停充，已跳过 $route"
						continue
					fi
				fi
				stop_nodes="$stop_nodes $route=$val"
				log_log=1
				stop_ok=1
				qsc_save_active_switch "$i"
				if [ "$first_only" = "first" ] || [ "$first_only" = "verify" ]; then
					return 0
				fi
			fi
		else
			val="$(echo "$i" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
			if qsc_write_node "$route" "$val"; then
				start_node="$route"
				start_val="$val"
				log_log2=1
				start_ok=1
			fi
		fi
	done
}

# 记录本次生效的开关条目（path,start=,stop=），供息屏期间单节点重申
qsc_save_active_switch() {
	local entry="$1"
	entry="$(echo "$entry" | tr -d ' \r\n')"
	[ -n "$entry" ] || return 1
	mkdir -p "$DATADIR" 2>/dev/null
	echo "$entry" >"$DATADIR/active_switch" 2>/dev/null
}

qsc_clear_active_switch() {
	rm -f "$DATADIR/active_switch" 2>/dev/null
}

# 粗判是否已停充（供 verify；MCA 写入后可能短暂仍显示 Charging，故 MCA 路径不依赖此函数）
qsc_charge_looks_stopped() {
	local st cur
	st="$(cat "$PSDIR/battery/status" 2>/dev/null | tr -d '\r\n')"
	case "$st" in
		"Not charging"|Discharging|Full) return 0 ;;
	esac
	cur="$(cat "$PSDIR/battery/current_now" 2>/dev/null | tr -d ' \r\n-')"
	case "$cur" in
		""|*[!0-9]*) return 1 ;;
	esac
	# |current_now| < 80mA 视为几乎无充电电流
	[ "$cur" -lt 80000 ] 2>/dev/null && return 0
	return 1
}

# 仅重写 data/active_switch；MCA 节点不加 chmod
qsc_reaffirm_active_stop() {
	local entry route val
	[ -f "$DATADIR/active_switch" ] || return 1
	entry="$(cat "$DATADIR/active_switch" 2>/dev/null | tr -d ' \r\n')"
	[ -n "$entry" ] || return 1
	route="$(echo "$entry" | sed -n 's/,start=.*//g;$p')"
	[ -f "$route" ] || return 1
	val="$(echo "$entry" | sed -n 's/.*,stop=//g;s/_/ /g;$p')"
	[ -n "$val" ] || return 1
	case "$route" in
		*handle_state*|*stop_handle_charge*)
			qsc_mca_raw_echo "$route" "$val" || return 1
			;;
		*)
			qsc_write_node "$route" "$val" || return 1
			;;
	esac
	stop_ok=1
	stop_nodes="$route=$val (reaffirm)"
	log_log=1
	return 0
}

# 停充且仍插电时可选持有内核 wakelock，避免深睡后节点被改回 → 回充亮屏死循环（魅族等）
QSC_WAKELOCK_NAME="qsc_stop_chg"
qsc_stop_wakelock_wanted() {
	local mode brand manufacturer
	mode="$(echo "$config_conf" | egrep '^stop_hold_wakelock=' | sed -n 's/stop_hold_wakelock=//g;$p')"
	[ -n "$mode" ] || mode="auto"
	case "$mode" in
		1|on|true) return 0 ;;
		0|off|false) return 1 ;;
		auto|*)
			brand="$(getprop ro.product.brand 2>/dev/null | tr '[:upper:]' '[:lower:]')"
			manufacturer="$(getprop ro.product.manufacturer 2>/dev/null | tr '[:upper:]' '[:lower:]')"
			case "$brand-$manufacturer" in
				*meizu*|*flyme*) return 0 ;;
			esac
			# 有 MCA 的小米机（17/K90 等）深睡也会改回 handle_state，持锁更稳
			if [ -f /sys/devices/platform/soc/soc:mca_business_charger/handle_state ] \
				|| [ -f /sys/devices/platform/soc/soc:mca_charger/handle_state ]; then
				return 0
			fi
			return 1
			;;
	esac
}

qsc_stop_wakelock_acquire() {
	[ -f /sys/power/wake_lock ] || return 1
	qsc_stop_wakelock_wanted || return 1
	if [ ! -f "$DATADIR/wakelock_held" ]; then
		echo "$QSC_WAKELOCK_NAME" > /sys/power/wake_lock 2>/dev/null || return 1
		touch "$DATADIR/wakelock_held" 2>/dev/null
		qsc_log_once wl_on debug "停充持锁：已阻止深睡回充（$QSC_WAKELOCK_NAME）"
	fi
	return 0
}

qsc_stop_wakelock_release() {
	[ -f /sys/power/wake_unlock ] || {
		rm -f "$DATADIR/wakelock_held" 2>/dev/null
		return 0
	}
	if [ -f "$DATADIR/wakelock_held" ]; then
		echo "$QSC_WAKELOCK_NAME" > /sys/power/wake_unlock 2>/dev/null
		rm -f "$DATADIR/wakelock_held" 2>/dev/null
		qsc_log_once_clear wl_on
	fi
	return 0
}

# 插电且处于停充态：仅 MCA/preferred 持续重申（非 MCA 停充成功后不再写节点，避免小米 OS2 闪充）
qsc_maintain_stop_while_plugged() {
	local online
	[ -f "$DATADIR/power_switch" ] || {
		qsc_stop_wakelock_release
		return 1
	}
	# 小米等停充后 dumpsys 可能短暂无 powered:true，改用 usb/online 判断仍插电
	if [ -z "$battery_powered" ]; then
		for online in "$PSDIR/usb/online" "$PSDIR/qc_usb/online" \
			"$PSDIR/wireless/online"; do
			if [ -f "$online" ] && [ "$(cat "$online" 2>/dev/null | tr -d ' \r\n')" = "1" ]; then
				battery_powered="powered: true"
				break
			fi
		done
	fi
	[ -n "$battery_powered" ] || {
		qsc_stop_wakelock_release
		return 1
	}
	qsc_stop_wakelock_acquire
	# MCA：系统会改回 handle_state，必须每轮重申
	if qsc_mca_write stop; then
		return 0
	fi
	# 用户实测 preferred 且标记 reassert 时才重申
	qsc_load_device_profile 2>/dev/null || true
	if [ "${QSC_REASSERT:-0}" = "1" ] && [ -n "$QSC_PREF_PATH" ] && [ -f "$QSC_PREF_PATH" ]; then
		qsc_pref_write stop && return 0
	fi
	# 通用节点：停充后静默，不写 active_switch
	return 0
}

# 组装 switch_list：扫描结果 + 兜底；并加载用户 power_switch
qsc_build_switch_list() {
	switch_list="$(cat "$LIST_SWITCH" 2>/dev/null)"
	switch_list="$switch_list $QSC_FALLBACK_SWITCHES"
	qsc_load_device_profile
	qsc_load_user_switches
}

# 实时探测并写入 MCA（不依赖过期 profile；不 chmod）
# 用法：qsc_mca_write stop | qsc_mca_write start
qsc_mca_write() {
	local label="$1"
	local val="" path="" cand
	case "$label" in
		stop) val=1 ;;
		start) val=0 ;;
		*) return 1 ;;
	esac

	qsc_load_device_profile 2>/dev/null || true

	# 1) 已缓存且仍存在的路径优先
	if [ -n "$QSC_MCA_PATH" ] && [ -f "$QSC_MCA_PATH" ]; then
		if qsc_mca_raw_echo "$QSC_MCA_PATH" "$val"; then
			path="$QSC_MCA_PATH"
		fi
	fi

	# 2) 候选列表实时扫（小米17: soc:mca_business_charger 优先）
	if [ -z "$path" ]; then
		for cand in $QSC_MCA_CANDIDATES; do
			[ -f "$cand" ] || continue
			if qsc_mca_raw_echo "$cand" "$val"; then
				path="$cand"
				break
			fi
		done
	fi

	# 3) find 兜底
	if [ -z "$path" ]; then
		cand="$(qsc_find_mca_path 2>/dev/null)" || cand=""
		if [ -n "$cand" ] && [ -f "$cand" ] && qsc_mca_raw_echo "$cand" "$val"; then
			path="$cand"
		fi
	fi

	# 4) stop_handle_charge 变体
	if [ -z "$path" ]; then
		for cand in $QSC_MCA_STOP_HANDLE_CANDIDATES; do
			[ -f "$cand" ] || continue
			if qsc_mca_raw_echo "$cand" "$val"; then
				path="$cand"
				break
			fi
		done
	fi

	if [ -z "$path" ]; then
		if qsc_debug_enabled; then
			qsc_log_once mca_path_missing debug \
				"MCA节点探测失败：profile_mca=$(qsc_profile_get mca 2>/dev/null) profile_path=$(qsc_profile_get mca_path 2>/dev/null)"
		fi
		return 1
	fi

	QSC_MCA=1
	QSC_MCA_PATH="$path"
	QSC_MCA_STOP=1
	QSC_MCA_START=0
	if [ "$(qsc_profile_get mca_path 2>/dev/null)" != "$path" ]; then
		qsc_write_device_profile "$path" >/dev/null 2>&1 || true
	fi
	if qsc_debug_enabled; then
		_mca_readback=""
		qsc_read_node "$path" && _mca_readback="$QSC_NODE_VAL"
		qsc_log_once "mca_write_$label" debug \
			"MCA写入：mode=$label path=$path request=$val readback=${_mca_readback:-?}"
	fi

	if [ "$label" = "stop" ]; then
		stop_nodes="$path=$val (MCA)"
		log_log=1
		stop_ok=1
		qsc_save_active_switch "${path},start=0,stop=1"
		# 软复核：MCA 常延迟生效，仅打日志不回滚
		_vd="$(echo "${config_conf:-}" | egrep '^switch_verify_sec=' | sed -n 's/switch_verify_sec=//g;$p')"
		_vd="$(qsc_clamp_int "${_vd:-1}" 0 5 1)"
		if [ "$_vd" -gt 0 ] 2>/dev/null; then
			sleep "$_vd"
			if ! qsc_charge_looks_stopped; then
				qsc_log_once mca_verify_soft debug "MCA 写入后瞬时仍显示充电中（常见，已保持停充写入）"
			fi
		fi
	else
		start_node="$path"
		start_val="$val"
		log_log2=1
		start_ok=1
	fi
	return 0
}

# 有 preferred_switch 时优先写该节点；MCA 机型仍优先 MCA
qsc_pref_write() {
	local mode="$1"
	local val
	qsc_load_device_profile
	[ -n "$QSC_PREF_PATH" ] && [ -f "$QSC_PREF_PATH" ] || return 1
	if [ "$mode" = "stop" ]; then
		val="$QSC_PREF_STOP"
		[ -n "$val" ] || return 1
		qsc_write_node "$QSC_PREF_PATH" "$val" || return 1
		stop_nodes="$QSC_PREF_PATH=$val (preferred)"
		log_log=1
		stop_ok=1
		qsc_save_active_switch "${QSC_PREF_PATH},start=${QSC_PREF_START},stop=${QSC_PREF_STOP}"
	else
		val="$QSC_PREF_START"
		[ -n "$val" ] || return 1
		qsc_write_node "$QSC_PREF_PATH" "$val" || return 1
		start_node="$QSC_PREF_PATH"
		start_val="$val"
		log_log2=1
		start_ok=1
	fi
	return 0
}

qsc_power_stop() {
	stop_ok=0
	stop_nodes=""
	# MCA 最先：直接 echo 1，不走全量列表（小米17/K90）
	if qsc_mca_write stop; then
		return
	fi
	if qsc_pref_write stop; then
		return
	fi
	if [ -n "$QSC_USER_SWITCHES" ]; then
		# 用户显式配置允许策略类节点
		qsc_write_switch_list stop "$QSC_USER_SWITCHES" verify 1
		if [ "$stop_ok" = "1" ]; then
			stop_nodes="$stop_nodes (user)"
			return
		fi
	fi
	# 常规开关：写入后校验是否真停充，避免「写成功但无效」导致闪充
	qsc_write_switch_list stop "$switch_list" verify
	if [ "$stop_ok" = "1" ]; then
		return
	fi
	# 末位兜底：电流墙 / 端口 suspend（仍做校验）
	qsc_write_switch_list stop "$QSC_LAST_RESORT_SWITCHES" verify
}

qsc_power_start() {
	start_ok=0
	start_node=""
	start_val=""
	if qsc_mca_write start; then
		qsc_clear_active_switch
		qsc_stop_wakelock_release
		return
	fi
	if qsc_pref_write start; then
		qsc_clear_active_switch
		qsc_stop_wakelock_release
		return
	fi
	if [ -n "$QSC_USER_SWITCHES" ]; then
		qsc_write_switch_list start "$QSC_USER_SWITCHES" "" 1
		if [ "$start_ok" = "1" ]; then
			qsc_clear_active_switch
			qsc_stop_wakelock_release
			return
		fi
	fi
	if [ -f "$DATADIR/active_switch" ]; then
		_as="$(cat "$DATADIR/active_switch" 2>/dev/null | tr -d ' \r\n')"
		_ar="$(echo "$_as" | sed -n 's/,start=.*//g;$p')"
		_av="$(echo "$_as" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
		if [ -n "$_ar" ] && [ -f "$_ar" ] && [ -n "$_av" ]; then
			# MCA 节点不用 chmod
			case "$_ar" in
				*handle_state*|*stop_handle_charge*)
					_ok=0
					qsc_mca_raw_echo "$_ar" "$_av" && _ok=1
					;;
				*)
					_ok=0
					qsc_write_node "$_ar" "$_av" && _ok=1
					;;
			esac
			if [ "$_ok" = "1" ]; then
				start_node="$_ar"
				start_val="$_av"
				log_log2=1
				start_ok=1
				qsc_clear_active_switch
				qsc_stop_wakelock_release
				return
			fi
		fi
	fi
	qsc_write_switch_list start "$switch_list"
	if [ "$start_ok" != "1" ]; then
		qsc_write_switch_list start "$QSC_LAST_RESORT_SWITCHES"
	fi
	qsc_clear_active_switch
	qsc_stop_wakelock_release
}

qsc_power_reset() {
	sleep 2
	qsc_power_stop
	sleep 1
	qsc_power_start
}

# 停充成功后多久之内不下「拔线」结论（秒）
QSC_UNPLUG_COOLDOWN=90

# 充电器是不是真被拔了。
#
# 不能只看 online 掉 0 或 status 不是 Charging：本模块的停充手段里就有端口
# suspend 与电流墙，写下去之后 usb/online 会变 0、status 也可能变成
# Discharging，看起来和拔线一模一样。据此还原节点就会在阈值处反复启停
# （电量到 100% 停充，下一轮误判成拔线又还原，于是立刻重新充电）。
#
# 所以这里只认「线还插着」的正面证据，任何一条成立就判定没拔：
#   1) present / type / VBUS 电压等物理存在信号
#   2) status = Not charging，其字面含义就是「有充电器但没在充」，
#      真拔线时内核约定报 Discharging
#   3) 距上次停充不足 QSC_UNPLUG_COOLDOWN 秒（停充瞬间信号会抖）
# 全都不成立才认为拔了。
qsc_charger_really_gone() {
	local p v st now last
	for p in "$PSDIR/usb/present" "$PSDIR/qc_usb/present" \
		"$PSDIR/wireless/present" "$PSDIR/ac/present"; do
		[ -f "$p" ] || continue
		v="$(cat "$p" 2>/dev/null | tr -d ' \r\n')"
		if [ "$v" = "1" ]; then
			qsc_log_once unplug_sig debug "$p=1，判定充电器仍在"
			return 1
		fi
	done
	# 充电口类型：插着线时报 USB_PD / USB_SDP 等，拔了报 Unknown
	for p in "$PSDIR/usb/real_type" "$PSDIR/usb/type"; do
		[ -f "$p" ] || continue
		v="$(cat "$p" 2>/dev/null | tr -d ' \r\n')"
		case "$v" in
			""|Unknown|UNKNOWN|None|NONE) ;;
			*)
				qsc_log_once unplug_sig debug "$p=$v，判定充电器仍在"
				return 1
				;;
		esac
	done
	# VBUS 还有电压说明线在（输入被 suspend 也不影响）
	v="$(cat "$PSDIR/usb/voltage_now" 2>/dev/null | tr -d ' \r\n-')"
	case "$v" in
		""|*[!0-9]*) ;;
		*)
			# 单位可能是 µV 或 mV，取 3V 作门槛
			if [ "$v" -gt 3000000 ] 2>/dev/null || \
				{ [ "$v" -gt 3000 ] 2>/dev/null && [ "$v" -lt 100000 ] 2>/dev/null; }; then
				qsc_log_once unplug_sig debug "usb/voltage_now=$v，判定充电器仍在"
				return 1
			fi
			;;
	esac
	st="$(cat "$PSDIR/battery/status" 2>/dev/null | tr -d '\r\n')"
	if [ "$st" = "Not charging" ]; then
		qsc_log_once unplug_sig debug "status=Not charging（有充电器但没在充），判定充电器仍在"
		return 1
	fi
	now="$(date +%s 2>/dev/null)"
	last="$(cat "$DATADIR/power_stop_ts" 2>/dev/null | tr -d ' \r\n')"
	case "$last" in ""|*[!0-9]*) last=0 ;; esac
	if [ -n "$now" ] && [ "$last" -gt 0 ] 2>/dev/null \
		&& [ "$((now - last))" -lt "$QSC_UNPLUG_COOLDOWN" ] 2>/dev/null; then
		qsc_log_once unplug_sig debug "距上次停充不足 ${QSC_UNPLUG_COOLDOWN}s，暂不判定拔线"
		return 1
	fi
	qsc_log_once_clear unplug_sig
	return 0
}

# 回收「孤儿停充」：节点还停在停充值上，但 data/power_switch 标记已经不在了。
# 这种状态没有任何常规流程会去管它（恢复流程以 power_switch 存在为前提），
# 结果就是手机一直充不进电而模块自认为一切正常。可能的来路：
# 进程在写完节点、还没 touch 标记之前被杀；data 目录被清过；旧版本留下的残留。
# 判定按「节点当前值 == 该条目的停充值」精确比对，不用 qsc_charge_looks_stopped：
# 后者在未插电时恒为真，会把没停充的机器也误判成停充。
# 返回 0 = 发现并处理了孤儿节点
qsc_orphan_stop_check() {
	local i route stop_val _sv cur hit=0
	[ -f "$DATADIR/power_switch" ] && return 1
	for i in $switch_list $QSC_USER_SWITCHES; do
		route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
		[ -n "$route" ] && [ -f "$route" ] || continue
		stop_val="$(echo "$i" | sed -n 's/.*,stop=//g;s/_/ /g;$p')"
		_sv="$(echo "$i" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
		[ -n "$stop_val" ] && [ -n "$_sv" ] || continue
		# 停充值与恢复值相同的条目无法区分状态，跳过
		[ "$stop_val" = "$_sv" ] && continue
		cur="$(cat "$route" 2>/dev/null | tr -d ' \r\n')"
		[ -n "$cur" ] || continue
		if [ "$cur" = "$stop_val" ]; then
			hit=1
			qsc_log warn "发现残留停充节点（无停充标记）：$route=$cur，正在还原"
			break
		fi
	done
	[ "$hit" = "1" ] || return 1
	qsc_power_start
	if [ "$start_ok" = "1" ]; then
		rm -f "$DATADIR/resume_fail_hint"
		qsc_log info "已还原残留停充节点 [$start_node <- $start_val]"
	else
		touch "$DATADIR/resume_fail_hint"
		qsc_log error "残留停充节点还原失败，手机可能充不进电"
	fi
	return 0
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
	local mca
	qsc_load_device_profile 2>/dev/null || true
	if [ -n "$QSC_MCA_PATH" ] && [ -f "$QSC_MCA_PATH" ]; then
		qsc_mca_raw_echo "$QSC_MCA_PATH" "${QSC_MCA_START:-0}"
		return 0
	fi
	for mca in $QSC_MCA_CANDIDATES $QSC_MCA_STOP_HANDLE_CANDIDATES; do
		if [ -f "$mca" ]; then
			qsc_mca_raw_echo "$mca" "0"
		fi
	done
}
