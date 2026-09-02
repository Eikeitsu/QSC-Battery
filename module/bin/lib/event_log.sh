#!/system/bin/sh
# 充电事件日志：插拔/停充/恢复/过温/健康等，charge_events.log，500 行轮转
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

# $1=事件类型(PLUG/UNPLUG/CHARGE_START/CHARGE_STOP/MAINTAIN/HEALTH/THERMAL/WARNING/CUSTOM)
# $2=detail(可空)
qsc_event_log() {
	local type="$1" detail="$2"
	[ -n "$type" ] || return 0
	local ts level temp
	ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" || ts=""
	level="$(qsc_cat_node "$PSDIR/battery/capacity" 2>/dev/null)"
	[ -z "$level" ] && level="--"
	temp="$(qsc_cat_node "$PSDIR/battery/temp" 2>/dev/null)"
	if [ -n "$temp" ] && [ "$temp" -gt 1000 ] 2>/dev/null; then
		temp=$((temp / 10))
	fi
	[ -z "$temp" ] && temp="--"
	# 归一化：过滤换行、%、度符号
	type="$(printf '%s' "$type" | tr -d '\r\n')"
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
