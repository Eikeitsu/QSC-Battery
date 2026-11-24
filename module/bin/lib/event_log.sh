#!/system/bin/sh
# 充电事件日志：插拔/停充/恢复/过温/健康等，写入 charge_events.log，超过上限自动轮转
# 格式：YYYY-MM-DD HH:MM:SS [EVENT] type level% temp°C detail

QSC_EVENT_LOG="${QSC_EVENT_LOG:-$DATADIR/charge_events.log}"
QSC_EVENT_LOG_MAX=500
QSC_EVENT_TMP="${QSC_EVENT_LOG}.tmp"

qsc_event_log_raw() {
	local line="$1"
	[ -n "$line" ] || return 0
	mkdir -p "$DATADIR" 2>/dev/null
	printf '%s\n' "$line" >>"$QSC_EVENT_LOG" 2>/dev/null || return 1
	local n
	n="$(wc -l <"$QSC_EVENT_LOG" 2>/dev/null | tr -d ' ')"
	case "$n" in ""|*[!0-9]*) n=0 ;; esac
	if [ "$n" -gt "$QSC_EVENT_LOG_MAX" ]; then
		tail -n $QSC_EVENT_LOG_MAX "$QSC_EVENT_LOG" >"$QSC_EVENT_TMP" 2>/dev/null &&
			mv -f "$QSC_EVENT_TMP" "$QSC_EVENT_LOG"
	fi
	return 0
}

# 同类事件去抖（秒）：避免假停充/边沿抖动连记多条
QSC_EVENT_DEDUP_SEC="${QSC_EVENT_DEDUP_SEC:-45}"

qsc_event_should_skip_dup() {
	local type="$1" now last gap f
	case "$type" in
		PLUG|UNPLUG|CHARGE_START|CHARGE_STOP|THERMAL) ;;
		*) return 1 ;;
	esac
	f="$DATADIR/.event_dedup_${type}"
	now="$(date +%s 2>/dev/null | tr -d ' \r\n')"
	case "$now" in ""|*[!0-9]*) return 1 ;; esac
	last="$(cat "$f" 2>/dev/null | tr -d ' \r\n')"
	case "$last" in ""|*[!0-9]*) last=0 ;; esac
	gap=$((now - last))
	if [ "$last" -gt 0 ] 2>/dev/null &&
		[ "$gap" -ge 0 ] 2>/dev/null &&
		[ "$gap" -lt "${QSC_EVENT_DEDUP_SEC:-45}" ] 2>/dev/null; then
		return 0
	fi
	printf '%s\n' "$now" >"$f" 2>/dev/null
	return 1
}

# $1=事件类型(PLUG/UNPLUG/CHARGE_START/CHARGE_STOP/MAINTAIN/HEALTH/THERMAL/WARNING/CUSTOM)
# $2=detail(可空)
qsc_event_log() {
	local type="$1" detail="$2"
	[ -n "$type" ] || return 0
	local ts level temp raw_temp
	type="$(printf '%s' "$type" | tr -d '\r\n')"
	qsc_event_should_skip_dup "$type" && return 0
	ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" || ts=""
	level="$(qsc_cat_node "$PSDIR/battery/capacity" 2>/dev/null)"
	[ -z "$level" ] && level="--"
	raw_temp="$(qsc_cat_node "$PSDIR/battery/temp" 2>/dev/null)"
	temp=""
	if [ -n "$raw_temp" ] && type qsc_normalize_temperature >/dev/null 2>&1; then
		temp="$(qsc_normalize_temperature "$raw_temp" 2>/dev/null)" || temp=""
	fi
	[ -z "$temp" ] && temp="--"
	detail="$(printf '%s' "$detail" | tr -d '\r\n')"
	qsc_event_log_raw "${ts} [EVENT] ${type} ${level}% ${temp}°C ${detail}"
}

# 便捷封装：插拔事件
qsc_event_plug()   { qsc_event_log PLUG         "$1"; }
qsc_event_unplug() { qsc_event_log UNPLUG       "$1"; }
qsc_event_start()  { qsc_event_log CHARGE_START "$1"; }
qsc_event_stop()   { qsc_event_log CHARGE_STOP  "$1"; }
qsc_event_hold()   { qsc_event_log MAINTAIN     "$1"; }
qsc_event_thermal(){ qsc_event_log THERMAL      "$1"; }
qsc_event_health() { qsc_event_log HEALTH       "$1"; }
qsc_event_warn()   { qsc_event_log WARNING      "$1"; }
