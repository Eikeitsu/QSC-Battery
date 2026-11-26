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
	local st
	if qsc_ps_read "$PSDIR/battery/status"; then
		st="$QSC_PS_VAL"
		case "$st" in
			Discharging|discharging) ;;
			*) return 1 ;;
		esac
	else
		return 1
	fi
	# 仅 status=Discharging 时，|I|>10mA 视为在耗电（含 mA 口径）
	qsc_ps_current_abs_ua || return 1
	[ "${QSC_PS_CUR_UA:-0}" -gt 10000 ] 2>/dev/null
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

# 充电口类型非 Unknown/None（含 MCA real_type：K90U 等 usb/type 常一直 Unknown）
qsc_ps_type_live() {
	local p v
	for p in "$PSDIR/usb/real_type" "$PSDIR/usb/type" \
		/sys/devices/platform/soc/soc:mca_business_charger/real_type \
		/sys/devices/platform/soc/soc:mca_charger/real_type \
		/sys/class/xm_power/charger/mca_business_charger/real_type; do
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

# K90U/MCA：未插电基线 real_type=Unknown、power_max=0、quick_charge_type=0；
# 插电后即使 online=0 / 掉 VBUS，这三项也会非空/非零，作强适配器证据。
qsc_ps_mca_adapter_live() {
	local p v
	for p in \
		/sys/devices/platform/soc/soc:mca_business_charger/real_type \
		/sys/devices/platform/soc/soc:mca_charger/real_type \
		/sys/class/xm_power/charger/mca_business_charger/real_type; do
		if qsc_ps_read "$p"; then
			v="$QSC_PS_VAL"
			case "$v" in
				""|Unknown|UNKNOWN|None|NONE) ;;
				*) return 0 ;;
			esac
		fi
	done
	for p in \
		/sys/devices/platform/soc/soc:mca_business_charger/power_max \
		/sys/devices/platform/soc/soc:mca_business_charger/quick_charge_type \
		/sys/devices/platform/soc/soc:mca_strategy_quick_charge/power_max \
		/sys/devices/platform/soc/soc:mca_strategy_quick_charge/quick_charge_type; do
		if qsc_ps_read "$p"; then
			v="$QSC_PS_VAL"
			case "$v" in
				""|*[!0-9]*) ;;
				0) ;;
				*) return 0 ;;
			esac
		fi
	done
	return 1
}

# 把 current_now 归一成 µA 绝对值（有的机报 mA）。
# 结果写入 QSC_PS_CUR_UA；失败返回 1。
qsc_ps_current_abs_ua() {
	local p cur cur_int
	QSC_PS_CUR_UA=0
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
			# |I|<10000 更像 mA（1.5A→1500）；常见充电电流远大于 10A(µA 口径)
			if [ "$cur_int" -gt 0 ] 2>/dev/null && [ "$cur_int" -lt 10000 ] 2>/dev/null; then
				cur_int=$((cur_int * 1000))
			fi
			QSC_PS_CUR_UA="$cur_int"
			return 0
		fi
	done
	return 1
}

# 明显在充电：|I|≥150mA。MTK/MCA 常 online=0 + Not charging 但仍大电流。
# K90U 未插电待机也常 |I|≥150mA 且 status=Discharging（诊断约 193~357mA）——
# 绝不能单靠绝对值判「在充」，否则 Action 假插电、DeepPark lean 永远进不去。
qsc_ps_charging_current_live() {
	if qsc_ps_looks_discharging; then
		return 1
	fi
	if qsc_ps_read "$PSDIR/battery/status"; then
		case "$QSC_PS_VAL" in
			Discharging|discharging) return 1 ;;
		esac
	fi
	qsc_ps_current_abs_ua || return 1
	[ "${QSC_PS_CUR_UA:-0}" -ge 150000 ] 2>/dev/null
}

# 电池侧充电态（非 Discharging）
qsc_ps_status_charge_like() {
	local st
	qsc_ps_read "$PSDIR/battery/status" || return 1
	st="$QSC_PS_VAL"
	case "$st" in
		Charging|charging|Full|full|"Not charging"|Notcharging|not_charging) return 0 ;;
	esac
	return 1
}

# XP 插拔事实（仅注入且文件可读时）。无 XP → 返回 1，调用方当没这路。
# 成功时：QSC_PS_XP_PLUG=plug|unplug，QSC_PS_XP_PLUG_AGE=秒。
qsc_ps_xp_plug_read() {
	local f=/data/system/qsc_xp_plug line st mt now
	QSC_PS_XP_PLUG=""
	QSC_PS_XP_PLUG_AGE=999999
	[ -f /data/system/qsc_xp_off ] && return 1
	type qsc_fg_xp_injected >/dev/null 2>&1 || return 1
	qsc_fg_xp_injected || return 1
	[ -f "$f" ] || return 1
	IFS= read -r line <"$f" 2>/dev/null || return 1
	st="$(printf '%s' "$line" | awk -F'\t' 'NF{print $NF; exit}' | tr -d ' \r\n')"
	case "$st" in
		plug|unplug) ;;
		*) return 1 ;;
	esac
	mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
	now="$(date +%s 2>/dev/null || echo 0)"
	case "$mt:$now" in *[!0-9:]*) return 1 ;; esac
	QSC_PS_XP_PLUG="$st"
	QSC_PS_XP_PLUG_AGE=$((now - mt))
	[ "$QSC_PS_XP_PLUG_AGE" -ge 0 ] 2>/dev/null || QSC_PS_XP_PLUG_AGE=999999
	return 0
}

# 近窗内 XP 报 unplug（否决粘 present）
qsc_ps_xp_plug_recent_unplug() {
	qsc_ps_xp_plug_read || return 1
	[ "$QSC_PS_XP_PLUG" = "unplug" ] || return 1
	[ "${QSC_PS_XP_PLUG_AGE:-999999}" -le "${QSC_XP_UNPLUG_HINT_SEC:-120}" ] 2>/dev/null
}

# XP 认为仍插着（边沿为 plug；年龄不限，直到下一次 unplug）
qsc_ps_xp_plug_says_plugged() {
	qsc_ps_xp_plug_read || return 1
	[ "$QSC_PS_XP_PLUG" = "plug" ]
}

# present=1 旁证：优先 VBUS / 类型 / 大电流；
# MCA 充电时常掉 VBUS 且 online=0，允许「present + 充电态」；
# 有 XP 时：近期 unplug 否决孤立 present；plug 可作为旁证。
# 停充标记冷却期内允许单信 present；
# 过期后孤立 present（且放电）视为未插电，避免粘 present + 残留 power_switch。
qsc_ps_present_corroborated() {
	local now last
	# XP 刚报拔线：不要用孤立 present 撑住「已插电」（K90U 粘 present）
	if qsc_ps_xp_plug_recent_unplug; then
		qsc_ps_dbg ps_xp_plug debug "XP 近期 unplug，否决孤立 present 旁证"
		return 1
	fi
	qsc_ps_vbus_live && return 0
	qsc_ps_type_live && return 0
	qsc_ps_mca_adapter_live && return 0
	qsc_ps_charging_current_live && return 0
	if qsc_ps_xp_plug_says_plugged; then
		qsc_ps_dbg ps_xp_plug debug "XP plug 旁证 present"
		return 0
	fi
	# MCA/xm_power：线还在但 VBUS/online 被掐时，允许 present + Charging/Full。
	# 不把 Not charging 算进来：K90U 未插电待机也常报 Not charging + 粘 present，
	# 会误判成已插电（Action 测开关、拔线检测都会坏）。停充维持靠 VBUS/类型/MCA 适配器信号。
	if type qsc_device_is_mca >/dev/null 2>&1 && qsc_device_is_mca; then
		if qsc_ps_read "$PSDIR/battery/status"; then
			case "$QSC_PS_VAL" in
				Charging|charging|Full|full)
					if ! qsc_ps_looks_discharging; then
						return 0
					fi
					;;
			esac
		fi
	fi
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

# online=1 不可单信：K90U 日志曾 status=Discharging/Not charging 仍误 PLUG。
# 可信条件：正在充 / 大电流，或停充插着时的 VBUS/MCA 旁证。
qsc_ps_online_corroborated() {
	if qsc_ps_read "$PSDIR/battery/status"; then
		case "$QSC_PS_VAL" in
			Charging|charging|Full|full) return 0 ;;
		esac
	fi
	qsc_ps_charging_current_live && return 0
	qsc_ps_vbus_live && return 0
	qsc_ps_mca_adapter_live && return 0
	return 1
}

qsc_ps_any_port_present() {
	local p
	for p in "$PSDIR/usb/present" "$PSDIR/qc_usb/present" \
		"$PSDIR/wireless/present" "$PSDIR/ac/present"; do
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			return 0
		fi
	done
	return 1
}

qsc_ps_any_port_online() {
	local p
	for p in "$PSDIR/usb/online" \
		"$PSDIR/qc_usb/online" \
		"$PSDIR/ac/online" \
		"$PSDIR/dc/online" \
		"$PSDIR/wireless/online" \
		"$PSDIR/charger/online" \
		"$PSDIR/battery/charger_online"; do
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			return 0
		fi
	done
	for p in "$PSDIR"/ucsi*/online "$PSDIR"/ucsi-source-psy*/online; do
		[ -e "$p" ] || continue
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			return 0
		fi
	done
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
			if ! qsc_ps_online_corroborated; then
				qsc_ps_dbg ps_online debug "忽略 $p=1：无 Charging/电流/VBUS/MCA 旁证"
				continue
			fi
			qsc_ps_dbg ps_online debug "判定已插电：$p=1"
			return 0
		fi
	done
	# K90U SM8750：UCSI 源 psy 在未插电 online=0；插电时常比 usb/online 更早变 1
	for p in "$PSDIR"/ucsi*/online "$PSDIR"/ucsi-source-psy*/online; do
		[ -e "$p" ] || continue
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			if ! qsc_ps_online_corroborated; then
				qsc_ps_dbg ps_online debug "忽略 UCSI online=1：无旁证（$p）"
				continue
			fi
			qsc_ps_dbg ps_online debug "判定已插电：UCSI online=1（$p）"
			return 0
		fi
	done
	# K90U / MCA：online 常为 0；present 需旁证（见 qsc_ps_present_corroborated）
	# 注意：未插电时 wireless/voltage_now≈电池电压、current 会镜像 battery——绝不能当 VBUS。
	for p in "$PSDIR/usb/present" "$PSDIR/qc_usb/present" \
		"$PSDIR/wireless/present" "$PSDIR/ac/present"; do
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			# VBUS/类型/MCA 适配器优先：停充后会放电，不能先因放电否决真插电
			if qsc_ps_vbus_live || qsc_ps_type_live || qsc_ps_mca_adapter_live; then
				qsc_ps_dbg ps_present debug "判定已插电：${p##*/}=1（有 VBUS/类型/MCA 旁证）"
				return 0
			fi
			# XP 近期 unplug + 放电：粘 present 直接丢掉（无 XP 不进此支）
			if qsc_ps_xp_plug_recent_unplug && qsc_ps_looks_discharging; then
				qsc_ps_dbg ps_xp_plug debug "忽略粘 ${p##*/}=1：XP unplug + 放电"
				continue
			fi
			if qsc_ps_looks_discharging; then
				qsc_ps_dbg ps_present debug "忽略孤立 ${p##*/}=1：伴随明显放电且无旁证"
				continue
			fi
			if ! qsc_ps_present_corroborated; then
				qsc_ps_dbg ps_present debug "忽略孤立 ${p##*/}=1（无 VBUS/类型/电流/MCA/XP 旁证）"
				continue
			fi
			qsc_ps_dbg ps_present debug "判定已插电：${p##*/}=1（online 可能为 0）"
			return 0
		fi
	done
	# 类型/MCA/VBUS 不能单信：K90U 未插电时类型偶发抖动，会假 PLUG/UNPLUG
	if qsc_ps_type_live || qsc_ps_mca_adapter_live; then
		if qsc_ps_any_port_online || qsc_ps_any_port_present || qsc_ps_vbus_live; then
			qsc_ps_dbg ps_type debug "判定已插电：类型/MCA + 端口/VBUS"
			return 0
		fi
		qsc_ps_dbg ps_type debug "忽略孤立类型/MCA（无 online/present/VBUS）"
	fi
	if qsc_ps_vbus_live; then
		v="$QSC_PS_VAL"
		# 放电且无端口时，孤立 VBUS 也不可靠；有 online/present 才认
		if qsc_ps_looks_discharging && ! qsc_ps_any_port_online && ! qsc_ps_any_port_present; then
			qsc_ps_dbg ps_voltage debug "忽略孤立 USB 电压（放电且无端口）：$v"
		else
			qsc_ps_dbg ps_voltage debug "判定已插电：USB 电压有效（$v）"
			return 0
		fi
	fi
	# Charging/Full：一加等机型未插电仍可能报 Charging——无端口证据时不得单信。
	# Not charging：无端口证据时忽略（K90U 未插电待机也报）。
	# 例外：非 Discharging 且 |I|≥150mA 视为仍在充（K60U MTK 常见 online=0 + Not charging）。
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
	qsc_ps_dbg ps_none debug "判定未插电：无 online/present/VBUS/类型/MCA/大电流证据"
	return 1
}

# 未插电且无停充维持时可跳过整轮；简介由 worker/XP，不再靠 FULL_MAX_GAP 强行满轮。
# （变量仍保留，深睡路径可能写入，仅作兼容/诊断。）
QSC_PS_FULL_MAX_GAP=1800
