#!/system/bin/sh
# power_saver: plugged detection
qsc_ps_plugged() {
	local now="${QSC_PS_NOW:-0}"
	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "$now" = "${QSC_PS_PLUG_CACHE_AT:-}" ]; then
		[ "${QSC_PS_PLUG_CACHE_VAL:-0}" = "1" ]
		return $?
	fi
	if qsc_ps_plugged_scan; then
		QSC_PS_PLUG_CACHE_VAL=1
		QSC_PS_PLUG_CACHE_AT="$now"
		return 0
	fi
	QSC_PS_PLUG_CACHE_VAL=0
	QSC_PS_PLUG_CACHE_AT="$now"
	return 1
}

# 明显在放电 / 靠电池：戳破 present 假插电。
# 注意：MCA/K90U 插电充电时常报 Not charging 且 |I| 很大——绝不能据此判放电，
# 否则会否决 present/VBUS，整轮 charge_eval=0（多机停充失效的常见原因）。
qsc_ps_looks_discharging() {
	local p cur cur_int st
	if qsc_ps_read "$PSDIR/battery/status"; then
		st="$QSC_PS_VAL"
		case "$st" in
			Discharging|discharging) ;;
			*) return 1 ;;
		esac
	else
		return 1
	fi
	for p in "$PSDIR/battery/current_now" \
		"$PSDIR/bms/current_now" \
		"$PSDIR/soc/current_now"; do
		if qsc_ps_read "$p"; then
			cur="$QSC_PS_VAL"
			case "$cur" in
				-|""|*[!0-9-]*) continue ;;
			esac
			cur_int="${cur#-}"
			case "$cur_int" in
				""|*[!0-9]*) continue ;;
			esac
			# 仅 status=Discharging 时，|I|>10mA 视为在耗电
			if [ "$cur_int" -gt 10000 ] 2>/dev/null; then
				return 0
			fi
			return 1
		fi
	done
	return 1
}

# USB VBUS 约 >3V（µV 或 mV）
qsc_ps_vbus_live() {
	local v
	qsc_ps_read "$PSDIR/usb/voltage_now" || return 1
	v="$QSC_PS_VAL"
	case "$v" in
		""|*[!0-9]*) return 1 ;;
	esac
	if [ "$v" -gt 3000000 ] 2>/dev/null || \
		{ [ "$v" -gt 3000 ] 2>/dev/null && [ "$v" -lt 100000 ] 2>/dev/null; }; then
		return 0
	fi
	return 1
}

# 充电口类型非 Unknown/None
qsc_ps_type_live() {
	local p v
	for p in "$PSDIR/usb/real_type" "$PSDIR/usb/type"; do
		if qsc_ps_read "$p"; then
			v="$QSC_PS_VAL"
			case "$v" in
				""|Unknown|UNKNOWN|None|NONE) ;;
				*) return 0 ;;
			esac
		fi
	done
	return 1
}

# 明显在充电：|I|≥150mA（µA）。MTK（K60U 等）常 online=0 + Not charging 但仍大电流。
qsc_ps_charging_current_live() {
	local p cur cur_int
	for p in "$PSDIR/battery/current_now" \
		"$PSDIR/bms/current_now" \
		"$PSDIR/soc/current_now"; do
		if qsc_ps_read "$p"; then
			cur="$QSC_PS_VAL"
			case "$cur" in
				-|""|*[!0-9-]*) continue ;;
			esac
			cur_int="${cur#-}"
			case "$cur_int" in
				""|*[!0-9]*) continue ;;
			esac
			if [ "$cur_int" -ge 150000 ] 2>/dev/null; then
				return 0
			fi
			return 1
		fi
	done
	return 1
}

# present=1 旁证：优先 VBUS / 类型。
# 停充标记存在时仅在冷却期内允许单信 present（MCA 刚停常掉 VBUS）；
# 过期后孤立 present 视为未插电，避免 K90U 粘 present + 残留 power_switch 永远清不掉。
qsc_ps_present_corroborated() {
	local now last
	qsc_ps_vbus_live && return 0
	qsc_ps_type_live && return 0
	if [ -f "$DATADIR/power_switch" ]; then
		now="$(date +%s 2>/dev/null)"
		last="$(cat "$DATADIR/power_stop_ts" 2>/dev/null | tr -d ' \r\n')"
		case "$last" in ""|*[!0-9]*) last=0 ;; esac
		if [ -n "$now" ] && [ "$last" -gt 0 ] 2>/dev/null \
			&& [ "$((now - last))" -lt "${QSC_UNPLUG_COOLDOWN:-90}" ] 2>/dev/null; then
			return 0
		fi
	fi
	return 1
}

qsc_ps_plugged_scan() {
	local p v
	for p in "$PSDIR/usb/online" \
		"$PSDIR/qc_usb/online" \
		"$PSDIR/ac/online" \
		"$PSDIR/dc/online" \
		"$PSDIR/wireless/online" \
		"$PSDIR/charger/online" \
		"$PSDIR/battery/charger_online"; do
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			qsc_ps_dbg ps_online debug "判定已插电：$p=1"
			return 0
		fi
	done
	# K90U / MCA：online 常为 0；present 需旁证（见 qsc_ps_present_corroborated）
	for p in "$PSDIR/usb/present" "$PSDIR/qc_usb/present" \
		"$PSDIR/wireless/present" "$PSDIR/ac/present"; do
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			# VBUS/类型优先：停充后会放电，不能先因放电否决真插电
			if qsc_ps_vbus_live || qsc_ps_type_live; then
				qsc_ps_dbg ps_present debug "判定已插电：${p##*/}=1（有 VBUS/类型旁证）"
				return 0
			fi
			if qsc_ps_looks_discharging; then
				qsc_ps_dbg ps_present debug "忽略孤立 ${p##*/}=1：伴随明显放电且无旁证"
				continue
			fi
			if ! qsc_ps_present_corroborated; then
				qsc_ps_dbg ps_present debug "忽略孤立 ${p##*/}=1（无 VBUS/类型/冷却期旁证）"
				continue
			fi
			qsc_ps_dbg ps_present debug "判定已插电：${p##*/}=1（online 可能为 0）"
			return 0
		fi
	done
	for p in "$PSDIR/usb/real_type" "$PSDIR/usb/type"; do
		if qsc_ps_read "$p"; then
			v="$QSC_PS_VAL"
			case "$v" in
				""|Unknown|UNKNOWN|None|NONE) ;;
				*)
					# 类型是强证据；停充维持中电池放电属预期，勿否决
					qsc_ps_dbg ps_type debug "判定已插电：接口类型 $v"
					return 0
					;;
			esac
		fi
	done
	if qsc_ps_vbus_live; then
		v="$QSC_PS_VAL"
		qsc_ps_dbg ps_voltage debug "判定已插电：USB 电压有效（$v）"
		return 0
	fi
	# Charging/Full：一加等机型未插电仍可能报 Charging——无端口证据时不得单信。
	# Not charging：无端口证据时忽略（K90U 未插电待机也报）。
	# 例外：|I|≥150mA 视为仍在充（K60U MTK 常见 online=0 + Not charging）。
	if qsc_ps_read "$PSDIR/battery/status"; then
		case "$QSC_PS_VAL" in
			Charging|Full)
				if qsc_ps_read "$PSDIR/battery/online" && [ "$QSC_PS_VAL" = "1" ]; then
					qsc_ps_dbg ps_status debug "判定已插电：battery/online=1"
					return 0
				fi
				if qsc_ps_charging_current_live; then
					qsc_ps_dbg ps_current debug "判定已插电：Charging/Full 且 |I|≥150mA"
					return 0
				fi
				qsc_ps_dbg ps_status debug "忽略孤立 status（无端口 online/present）"
				;;
			"Not charging")
				if qsc_ps_looks_discharging; then
					qsc_ps_dbg ps_status debug "判定未插电：Not charging 且放电中"
					return 1
				fi
				if qsc_ps_charging_current_live; then
					qsc_ps_dbg ps_current debug "判定已插电：Not charging 但 |I|≥150mA（MTK 常见）"
					return 0
				fi
				qsc_ps_dbg ps_status debug "忽略孤立 Not charging（无端口证据，避免假插电）"
				;;
		esac
	fi
	qsc_ps_dbg ps_none debug "判定未插电：无 online/present/VBUS/类型/大电流证据"
	return 1
}

# 未插电且无停充维持时可跳过整轮；简介由 worker/XP，不再靠 FULL_MAX_GAP 强行满轮。
# （变量仍保留，深睡路径可能写入，仅作兼容/诊断。）
QSC_PS_FULL_MAX_GAP=1800
