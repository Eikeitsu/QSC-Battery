#!/system/bin/sh
# charge: unplug detect / orphan stop

# 插电→未插电边沿：记 UNPLUG（不依赖是否已停充）。
# lean 跳过 qsc_switch 时也会调这里，避免 charge_events 漏拔线。
# 返回 0=本轮新记了边沿；1=本已是未插电态。
qsc_note_unplug_edge() {
	local detail="${1:-充电器拔出}"
	[ "${module_off:-0}" = "1" ] && return 1
	# 从未认为插过电：不记假拔线
	[ -f "$DATADIR/power_on" ] || [ -f "$DATADIR/.plug_seen" ] || return 1
	rm -f "$DATADIR/power_on" "$DATADIR/now_c" 2>/dev/null
	touch "$DATADIR/power_off" 2>/dev/null
	if [ -f "$DATADIR/.unplug_noted" ]; then
		return 1
	fi
	touch "$DATADIR/.unplug_noted" 2>/dev/null
	type qsc_event_unplug >/dev/null 2>&1 &&
		qsc_event_unplug "$detail"
	qsc_log info "已拔出充电器"
	return 0
}

qsc_charger_really_gone() {
	local p v now last _has_side
	# K90U：MCA 适配器信号仍有效 = 线还在（online 常为 0）
	if type qsc_ps_mca_adapter_live >/dev/null 2>&1 && qsc_ps_mca_adapter_live; then
		qsc_log_once unplug_sig debug "MCA real_type/power_max 有效，判定充电器仍在"
		return 1
	fi
	# UCSI / Pixel TCPM online=1 也算线在
	for p in "$PSDIR"/ucsi*/online "$PSDIR"/ucsi-source-psy*/online \
		"$PSDIR"/tcpm-source-psy*/online "$PSDIR"/tcpm*/online; do
		[ -e "$p" ] || continue
		v="$(cat "$p" 2>/dev/null | tr -d ' \r\n')"
		if [ "$v" = "1" ]; then
			qsc_log_once unplug_sig debug "$p=1，判定充电器仍在"
			return 1
		fi
	done
	for p in "$PSDIR/usb/present" "$PSDIR/qc_usb/present" \
		"$PSDIR/wireless/present" "$PSDIR/ac/present" \
		"$PSDIR/main-charger/present"; do
		[ -f "$p" ] || continue
		v="$(cat "$p" 2>/dev/null | tr -d ' \r\n')"
		if [ "$v" = "1" ]; then
			# 先看 VBUS/类型/MCA：停充后电池常报 Discharging，不能用「放电」否决真插电。
			_has_side=0
			if type qsc_ps_vbus_live >/dev/null 2>&1 && qsc_ps_vbus_live; then
				_has_side=1
			elif type qsc_ps_type_live >/dev/null 2>&1 && qsc_ps_type_live; then
				_has_side=1
			elif type qsc_ps_mca_adapter_live >/dev/null 2>&1 && qsc_ps_mca_adapter_live; then
				_has_side=1
			fi
			if [ "$_has_side" = "1" ]; then
				qsc_log_once unplug_sig debug "$p=1 且有 VBUS/类型/MCA 旁证，判定充电器仍在"
				return 1
			fi
			# 孤立 present：放电时不可信（粘 present）；冷却期内允许暂留。
			if type qsc_ps_looks_discharging >/dev/null 2>&1 && qsc_ps_looks_discharging; then
				qsc_log_once unplug_sig debug "$p=1 但明显放电且无旁证，不据此保留停充"
				continue
			fi
			if [ -f "$DATADIR/power_switch" ]; then
				now="$(date +%s 2>/dev/null)"
				last="$(cat "$DATADIR/power_stop_ts" 2>/dev/null | tr -d ' \r\n')"
				case "$last" in ""|*[!0-9]*) last=0 ;; esac
				if [ -n "$now" ] && [ "$last" -gt 0 ] 2>/dev/null \
					&& [ "$((now - last))" -lt "$QSC_UNPLUG_COOLDOWN" ] 2>/dev/null; then
					qsc_log_once unplug_sig debug "$p=1 停充冷却期内，暂不判定拔线"
					return 1
				fi
			fi
			qsc_log_once unplug_sig debug "忽略孤立 $p=1（无旁证/已过冷却）"
		fi
	done
	# 充电口 / MCA 类型：插着线非 Unknown；拔了报 Unknown（K90U 未插电诊断即此）
	if type qsc_ps_type_live >/dev/null 2>&1 && qsc_ps_type_live; then
		qsc_log_once unplug_sig debug "接口/MCA 类型有效，判定充电器仍在"
		return 1
	fi
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
	# VBUS 还有电压说明线在（input_suspend 也不掉 VBUS）
	# 注意：K90U 未插电时 wireless/voltage_now 会镜像电池电压，绝不能当 VBUS。
	v="$(cat "$PSDIR/usb/voltage_now" 2>/dev/null | tr -d ' \r\n-')"
	case "$v" in
		""|*[!0-9]*) ;;
		*)
			# µV>3V，或 mV 3..20V；Pixel 未插电噪声≈25000 不得当 25V
			if [ "$v" -gt 3000000 ] 2>/dev/null || \
				{ [ "$v" -ge 3000 ] 2>/dev/null && [ "$v" -le 20000 ] 2>/dev/null; }; then
				qsc_log_once unplug_sig debug "usb/voltage_now=$v，判定充电器仍在"
				return 1
			fi
			;;
	esac
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
# 未插电时跳过：小米等 OEM 省电/电池健康也会把节点写成停充值，还原只会反复 WARN。
# 返回 0 = 发现并处理了孤儿节点
qsc_orphan_stop_check() {
	local i route stop_val _sv cur hit=0
	[ -f "$DATADIR/power_switch" ] && return 1
	# 只在「可能想充电」时处理：已插电，或侧路仍显示 VBUS/类型
	if type qsc_ps_plugged >/dev/null 2>&1; then
		qsc_ps_plugged || return 1
	elif type qsc_ps_vbus_live >/dev/null 2>&1; then
		qsc_ps_vbus_live || return 1
	fi
	for i in $switch_list $QSC_USER_SWITCHES; do
		qsc_parse_normalized_switch_entry "$i" || continue
		route="$QSC_SW_ROUTE"
		[ -n "$route" ] && [ -f "$route" ] || continue
		stop_val="$QSC_SW_STOP"
		_sv="$QSC_SW_START"
		case "$_sv" in
			*_*) _sv="$(printf '%s' "$_sv" | tr '_' ' ')" ;;
		esac
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
