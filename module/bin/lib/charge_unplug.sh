#!/system/bin/sh
# charge: unplug detect / orphan stop
qsc_charger_really_gone() {
	local p v now last _has_side
	for p in "$PSDIR/usb/present" "$PSDIR/qc_usb/present" \
		"$PSDIR/wireless/present" "$PSDIR/ac/present"; do
		[ -f "$p" ] || continue
		v="$(cat "$p" 2>/dev/null | tr -d ' \r\n')"
		if [ "$v" = "1" ]; then
			# 与插电扫描一致：孤立 present 不够；VBUS/类型旁证才长期保留。
			# 停充维持中仅在冷却期内允许单信 present，避免 K90U 粘 present 永不拔线。
			if type qsc_ps_looks_discharging >/dev/null 2>&1 && qsc_ps_looks_discharging; then
				qsc_log_once unplug_sig debug "$p=1 但明显放电，不据此保留停充"
				continue
			fi
			_has_side=0
			if type qsc_ps_vbus_live >/dev/null 2>&1 && qsc_ps_vbus_live; then
				_has_side=1
			elif type qsc_ps_type_live >/dev/null 2>&1 && qsc_ps_type_live; then
				_has_side=1
			fi
			if [ "$_has_side" = "1" ]; then
				qsc_log_once unplug_sig debug "$p=1 且有 VBUS/类型旁证，判定充电器仍在"
				return 1
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
	# 充电口类型：插着线时报 USB_PD / USB_SDP 等，拔了报 Unknown
	for p in "$PSDIR/usb/real_type" "$PSDIR/usb/type"; do
		[ -f "$p" ] || continue
		v="$(cat "$p" 2>/dev/null | tr -d ' \r\n')"
		case "$v" in
			""|Unknown|UNKNOWN|None|NONE) ;;
			*)
				if type qsc_ps_looks_discharging >/dev/null 2>&1 && qsc_ps_looks_discharging; then
					qsc_log_once unplug_sig debug "$p=$v 但明显放电，不据此保留停充"
					continue
				fi
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
				if type qsc_ps_looks_discharging >/dev/null 2>&1 && qsc_ps_looks_discharging; then
					qsc_log_once unplug_sig debug "usb/voltage_now=$v 但明显放电，不据此保留停充"
				else
					qsc_log_once unplug_sig debug "usb/voltage_now=$v，判定充电器仍在"
					return 1
				fi
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
