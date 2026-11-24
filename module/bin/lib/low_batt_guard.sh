#!/system/bin/sh
# 低电/过温防护（冷门）：提醒 + 自动关机。相关阈值均为 0 时立刻返回，零额外开销。
# 建议值（启用时）：warn=15 shutdown=5 temp=55；关机前须开机≥15 分钟（可配）。

qsc_notify_system() {
	local tag="$1" title="$2" body="$3"
	[ -n "$tag" ] && [ -n "$body" ] || return 0
	title="${title:-充电控制}"
	tag="$(printf '%s' "$tag" | tr -d "'\"\r\n")"
	title="$(printf '%s' "$title" | tr -d "'\"\r\n")"
	body="$(printf '%s' "$body" | tr -d "'\"\r\n")"
	if command -v su >/dev/null 2>&1; then
		su -lp 2000 -c "cmd notification post -t '$title' '$tag' '$body'" >/dev/null 2>&1 && return 0
	fi
	cmd notification post -t "$title" "$tag" "$body" >/dev/null 2>&1 || true
}

qsc_low_batt_resolve() {
	local w s d u t
	w="${QSCV_low_batt_warn:-0}"
	s="${QSCV_low_batt_shutdown:-0}"
	case "$s" in
		""|0)
			case "${QSCV_shut_down:-}" in
				""|0) ;;
				*) s="${QSCV_shut_down}" ;;
			esac
			;;
	esac
	d="${QSCV_low_batt_shutdown_delay_sec:-60}"
	u="${QSCV_low_batt_shutdown_min_uptime_sec:-900}"
	t="${QSCV_low_batt_temp_shutdown:-0}"
	w="$(qsc_clamp_int "$w" 0 100 0)"
	s="$(qsc_clamp_int "$s" 0 15 0)"
	d="$(qsc_clamp_int "$d" 10 300 60)"
	u="$(qsc_clamp_int "$u" 0 7200 900)"
	t="$(qsc_clamp_int "$t" 0 70 0)"
	if [ "$w" -gt 0 ] 2>/dev/null && [ "$s" -gt 0 ] 2>/dev/null &&
		[ "$s" -ge "$w" ] 2>/dev/null; then
		s=$((w - 1))
		[ "$s" -lt 1 ] 2>/dev/null && s=0
	fi
	QSC_LOW_BATT_WARN="$w"
	QSC_LOW_BATT_SHUT="$s"
	QSC_LOW_BATT_DELAY="$d"
	QSC_LOW_BATT_MIN_UPTIME="$u"
	QSC_LOW_BATT_TEMP_SHUT="$t"
}

qsc_low_batt_uptime_ok() {
	local need up
	need="${QSC_LOW_BATT_MIN_UPTIME:-900}"
	[ "$need" -le 0 ] 2>/dev/null && return 0
	up="$(cut -d. -f1 /proc/uptime 2>/dev/null)"
	case "$up" in
		""|*[!0-9]*) return 1 ;;
	esac
	[ "$up" -ge "$need" ] 2>/dev/null
}

qsc_low_batt_level() {
	local lv
	lv="${battery_level:-}"
	case "$lv" in
		""|*[!0-9]*)
			lv="${QSC_BATTERY_LEVEL:-}"
			;;
	esac
	case "$lv" in
		""|*[!0-9]*)
			if type qsc_ps_read >/dev/null 2>&1; then
				if qsc_ps_read "${PSDIR:-/sys/class/power_supply}/battery/capacity"; then
					lv="$QSC_PS_VAL"
				fi
			elif [ -r "${PSDIR:-/sys/class/power_supply}/battery/capacity" ]; then
				lv="$(cat "${PSDIR:-/sys/class/power_supply}/battery/capacity" 2>/dev/null | tr -d ' \r\n')"
			fi
			;;
	esac
	case "$lv" in
		""|*[!0-9]*) return 1 ;;
	esac
	QSC_LOW_BATT_LEVEL="$lv"
	return 0
}

qsc_low_batt_temp() {
	local raw t
	t="${temperature:-}"
	case "$t" in
		""|*[!0-9]*)
			raw=
			if type qsc_ps_read >/dev/null 2>&1; then
				if qsc_ps_read "${PSDIR:-/sys/class/power_supply}/battery/temp"; then
					raw="$QSC_PS_VAL"
				fi
			fi
			[ -n "$raw" ] ||
				raw="$(cat "${PSDIR:-/sys/class/power_supply}/battery/temp" 2>/dev/null | tr -d ' \r\n')"
			if [ -n "$raw" ] && type qsc_normalize_temperature >/dev/null 2>&1; then
				t="$(qsc_normalize_temperature "$raw" 2>/dev/null)" || t=""
			else
				t="$raw"
			fi
			;;
	esac
	case "$t" in
		""|*[!0-9]*) return 1 ;;
	esac
	QSC_LOW_BATT_TEMP="$t"
	return 0
}

qsc_low_batt_clear_marks() {
	rm -f "$DATADIR/low_batt_warned" "$DATADIR/low_batt_shutting" 2>/dev/null
	type qsc_notify_cancel >/dev/null 2>&1 && qsc_notify_cancel qsc_low
	type qsc_notify_cancel >/dev/null 2>&1 && qsc_notify_cancel qsc_halt
}

qsc_low_batt_do_shutdown() {
	local why="${1:-防护}"
	qsc_log warn "低电防护：${why} 触发关机（电量${QSC_LOW_BATT_LEVEL:-?} 温度${QSC_LOW_BATT_TEMP:-?}）"
	svc power shutdown >/dev/null 2>&1 && return 0
	reboot -p >/dev/null 2>&1 && return 0
	qsc_log error "低电防护：关机命令失败"
	return 1
}

# reason=capacity|temp
qsc_low_batt_shutdown_countdown() {
	local reason="${1:-capacity}" delay left chunk title body
	[ -f "$DATADIR/low_batt_shutting" ] && return 0
	touch "$DATADIR/low_batt_shutting" 2>/dev/null
	delay="${QSC_LOW_BATT_DELAY:-60}"
	if [ "$reason" = "temp" ]; then
		title="电池过热"
		body="当前 ${QSC_LOW_BATT_TEMP}°C · 约 ${delay} 秒后关机（降温可取消）"
	else
		title="电量过低"
		body="当前 ${QSC_LOW_BATT_LEVEL}% · 约 ${delay} 秒后关机（插电可取消）"
	fi
	qsc_notify_system qsc_halt "$title" "$body"
	left="$delay"
	while [ "$left" -gt 0 ] 2>/dev/null; do
		if [ "$reason" = "capacity" ]; then
			if type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
				qsc_low_batt_clear_marks
				qsc_notify_system qsc_halt "已取消关机" "检测到充电，已取消自动关机"
				return 0
			fi
		fi
		chunk=5
		[ "$left" -lt "$chunk" ] 2>/dev/null && chunk="$left"
		sleep "$chunk"
		left=$((left - chunk))
		if [ "$reason" = "temp" ]; then
			qsc_low_batt_temp || true
			if [ -n "${QSC_LOW_BATT_TEMP:-}" ] &&
				[ "${QSC_LOW_BATT_TEMP_SHUT:-0}" -gt 0 ] 2>/dev/null &&
				[ "$QSC_LOW_BATT_TEMP" -lt "$QSC_LOW_BATT_TEMP_SHUT" ] 2>/dev/null; then
				qsc_low_batt_clear_marks
				qsc_notify_system qsc_halt "已取消关机" "温度已下降，已取消自动关机"
				return 0
			fi
		else
			qsc_low_batt_level || true
			if [ -n "${QSC_LOW_BATT_LEVEL:-}" ] &&
				[ "${QSC_LOW_BATT_SHUT:-0}" -gt 0 ] 2>/dev/null &&
				[ "$QSC_LOW_BATT_LEVEL" -gt "$QSC_LOW_BATT_SHUT" ] 2>/dev/null; then
				qsc_low_batt_clear_marks
				qsc_notify_system qsc_halt "已取消关机" "电量已回升，已取消自动关机"
				return 0
			fi
		fi
	done
	if [ "$reason" = "capacity" ] &&
		type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
		qsc_low_batt_clear_marks
		return 0
	fi
	if [ "$reason" = "temp" ]; then
		qsc_low_batt_do_shutdown "过温${QSC_LOW_BATT_TEMP:-?}°C"
	else
		qsc_low_batt_do_shutdown "低电${QSC_LOW_BATT_LEVEL:-?}%"
	fi
	rm -f "$DATADIR/low_batt_shutting" 2>/dev/null
}

qsc_low_batt_guard() {
	local clear_at
	qsc_low_batt_resolve
	# 默关：零开销早退
	[ "${QSC_LOW_BATT_WARN:-0}" = "0" ] &&
		[ "${QSC_LOW_BATT_SHUT:-0}" = "0" ] &&
		[ "${QSC_LOW_BATT_TEMP_SHUT:-0}" = "0" ] && return 0

	# 过温关机：插电也生效
	if [ "${QSC_LOW_BATT_TEMP_SHUT:-0}" -gt 0 ] 2>/dev/null; then
		if qsc_low_batt_temp &&
			[ "$QSC_LOW_BATT_TEMP" -ge "$QSC_LOW_BATT_TEMP_SHUT" ] 2>/dev/null; then
			qsc_low_batt_shutdown_countdown temp
			return 0
		fi
	fi

	# 仅低电提醒/关机需要未插电
	[ "${QSC_LOW_BATT_WARN:-0}" = "0" ] && [ "${QSC_LOW_BATT_SHUT:-0}" = "0" ] && return 0

	if type qsc_ps_plugged >/dev/null 2>&1; then
		if qsc_ps_plugged; then
			if [ -f "$DATADIR/low_batt_warned" ] || [ -f "$DATADIR/low_batt_shutting" ]; then
				# 过温倒计时中途插电不在此清（过温路径已 return）；仅清低电闩锁
				rm -f "$DATADIR/low_batt_warned" 2>/dev/null
				[ ! -f "$DATADIR/low_batt_shutting" ] ||
					qsc_low_batt_clear_marks
			fi
			return 0
		fi
	elif [ -n "${battery_powered:-}" ]; then
		rm -f "$DATADIR/low_batt_warned" 2>/dev/null
		return 0
	fi

	qsc_low_batt_level || return 0

	if [ "${QSC_LOW_BATT_WARN:-0}" -gt 0 ] 2>/dev/null; then
		clear_at=$((QSC_LOW_BATT_WARN + 5))
		[ "$clear_at" -gt 100 ] 2>/dev/null && clear_at=100
		if [ "$QSC_LOW_BATT_LEVEL" -gt "$clear_at" ] 2>/dev/null; then
			rm -f "$DATADIR/low_batt_warned" 2>/dev/null
			type qsc_notify_cancel >/dev/null 2>&1 && qsc_notify_cancel qsc_low
		fi
	fi

	if [ "${QSC_LOW_BATT_SHUT:-0}" -gt 0 ] 2>/dev/null &&
		[ "$QSC_LOW_BATT_LEVEL" -le "$QSC_LOW_BATT_SHUT" ] 2>/dev/null; then
		if qsc_low_batt_uptime_ok; then
			qsc_low_batt_shutdown_countdown capacity
		else
			qsc_log info "低电防护：已达关机电量但开机未满 ${QSC_LOW_BATT_MIN_UPTIME}s，暂不关机"
		fi
		return 0
	fi

	if [ "${QSC_LOW_BATT_WARN:-0}" -gt 0 ] 2>/dev/null &&
		[ "$QSC_LOW_BATT_LEVEL" -le "$QSC_LOW_BATT_WARN" ] 2>/dev/null &&
		[ ! -f "$DATADIR/low_batt_warned" ]; then
		touch "$DATADIR/low_batt_warned" 2>/dev/null
		qsc_notify_system qsc_low "电量偏低" \
			"当前 ${QSC_LOW_BATT_LEVEL}%，建议接入电源"
		qsc_log info "低电防护：已提醒 ${QSC_LOW_BATT_LEVEL}% ≤ ${QSC_LOW_BATT_WARN}%"
	fi
	return 0
}
