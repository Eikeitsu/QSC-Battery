#!/system/bin/sh
# 充放电历史采样：data/charge_history.csv（约 24h）

QSC_HISTORY_FILE="${QSC_HISTORY_FILE:-$DATADIR/charge_history.csv}"
QSC_HISTORY_MAX_LINES=1600

# 充电来源：usb | wireless | none
qsc_charge_source() {
	local p
	for p in /sys/class/power_supply/usb/online /sys/class/power_supply/qc_usb/online \
		/sys/class/power_supply/ac/online /sys/class/power_supply/dc/online; do
		[ -f "$p" ] || continue
		[ "$(cat "$p" 2>/dev/null | tr -d ' \r\n')" = "1" ] && {
			echo usb
			return 0
		}
	done
	for p in /sys/class/power_supply/wireless/online /sys/class/power_supply/wireless/present \
		/sys/class/power_supply/wireless_chg/online; do
		[ -f "$p" ] || continue
		[ "$(cat "$p" 2>/dev/null | tr -d ' \r\n')" = "1" ] && {
			echo wireless
			return 0
		}
	done
	echo none
	return 1
}

# $1=包名列表文件（一行一个）命中前台或进程则 0
qsc_pkg_list_hit() {
	local list_file="$1" pkg focus ps_line
	[ -f "$list_file" ] && [ -s "$list_file" ] || return 1
	while IFS= read -r pkg || [ -n "$pkg" ]; do
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
		[ -n "$pkg" ] || continue
		ps_line="$(ps -ef 2>/dev/null | egrep "$pkg" | egrep -v "${pkg}:" | egrep -v 'egrep')"
		if [ -n "$ps_line" ]; then
			return 0
		fi
	done <"$list_file"
	focus="$(dumpsys window 2>/dev/null | grep 'mCurrentFocus' | tail -1)"
	[ -z "$focus" ] && focus="$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1)"
	if [ -n "$focus" ]; then
		while IFS= read -r pkg || [ -n "$pkg" ]; do
			pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
			[ -n "$pkg" ] || continue
			echo "$focus" | grep -q "$pkg" && return 0
		done <"$list_file"
	fi
	return 1
}

# 将逗号/空格分隔包名写入临时文件
qsc_write_pkg_tmp() {
	local raw="$1" out="$2"
	printf '%s' "$raw" | tr ',; ' '\n' | sed '/^$/d' >"$out" 2>/dev/null
}

# AccA / ACC 等限流模块探测 → data/compat_hint
qsc_detect_compat_modules() {
	local hit="" id
	for id in acc AccA Advanced_Charging_Controller advanced_charging_controller ACC \
		vr25acc charge-control; do
		if [ -d "/data/adb/modules/$id" ] && [ ! -f "/data/adb/modules/$id/disable" ]; then
			hit="${hit}${hit:+,}$id"
		fi
	done
	# 目录名模糊
	if [ -z "$hit" ]; then
		for d in /data/adb/modules/*; do
			[ -d "$d" ] || continue
			[ -f "$d/disable" ] && continue
			base="${d##*/}"
			case "$base" in
				*[Aa][Cc][Cc]*|*charging*ontrol*|*ChargeControl*)
					hit="${hit}${hit:+,}$base"
					;;
			esac
		done
	fi
	mkdir -p "$DATADIR" 2>/dev/null
	if [ -n "$hit" ]; then
		echo "$hit" >"$DATADIR/compat_hint" 2>/dev/null
		return 0
	fi
	rm -f "$DATADIR/compat_hint" 2>/dev/null
	return 1
}

qsc_history_sample() {
	local enable="$1" interval="$2" level="$3" temp="$4"
	local now last cur status src line n
	enable="$(qsc_clamp_int "${enable:-1}" 0 1 1)"
	[ "$enable" = "1" ] || return 0
	interval="$(qsc_clamp_int "${interval:-60}" 15 600 60)"
	now="$(date +%s 2>/dev/null)" || return 0
	[ -n "$now" ] || return 0
	last="$(cat "$DATADIR/history_last_ts" 2>/dev/null | tr -d ' \r\n')"
	case "$last" in ""|*[!0-9]*) last=0 ;; esac
	if [ "$((now - last))" -lt "$interval" ] 2>/dev/null; then
		return 0
	fi
	echo "$now" >"$DATADIR/history_last_ts" 2>/dev/null
	cur="$(cat /sys/class/power_supply/battery/current_now 2>/dev/null | tr -d ' \r\n')"
	status="$(cat /sys/class/power_supply/battery/status 2>/dev/null | tr -d ' \r\n')"
	src="$(qsc_charge_source 2>/dev/null)"
	[ -n "$level" ] || level="$(cat /sys/class/power_supply/battery/capacity 2>/dev/null | tr -d ' \r\n')"
	[ -n "$temp" ] || temp="--"
	mkdir -p "$DATADIR" 2>/dev/null
	if [ ! -f "$QSC_HISTORY_FILE" ]; then
		echo "ts,level,temp,current_ua,status,source" >"$QSC_HISTORY_FILE"
	fi
	# CSV 安全：字段去逗号
	level="$(printf '%s' "$level" | tr -d ',')"
	temp="$(printf '%s' "$temp" | tr -d ',')"
	cur="$(printf '%s' "$cur" | tr -d ',')"
	status="$(printf '%s' "$status" | tr -d ',')"
	src="$(printf '%s' "$src" | tr -d ',')"
	echo "${now},${level},${temp},${cur},${status},${src}" >>"$QSC_HISTORY_FILE"
	n="$(wc -l <"$QSC_HISTORY_FILE" 2>/dev/null | tr -d ' ')"
	if [ -n "$n" ] && [ "$n" -gt "$QSC_HISTORY_MAX_LINES" ] 2>/dev/null; then
		# 保留表头 + 末尾
		{
			head -n 1 "$QSC_HISTORY_FILE"
			tail -n $((QSC_HISTORY_MAX_LINES - 1)) "$QSC_HISTORY_FILE"
		} >"$QSC_HISTORY_FILE.tmp" 2>/dev/null && mv -f "$QSC_HISTORY_FILE.tmp" "$QSC_HISTORY_FILE"
	fi
	# 丢弃 36h 以前
	if [ -n "$now" ]; then
		awk -F, -v cut="$((now - 129600))" 'NR==1 || $1+0>=cut' "$QSC_HISTORY_FILE" >"$QSC_HISTORY_FILE.trim" 2>/dev/null \
			&& mv -f "$QSC_HISTORY_FILE.trim" "$QSC_HISTORY_FILE"
	fi
}

# 根据是否停充维持，写入本轮建议 sleep 秒数
qsc_write_loop_sleep() {
	local normal="$1" maintain="$2"
	normal="$(qsc_clamp_int "${normal:-3}" 2 30 3)"
	maintain="$(qsc_clamp_int "${maintain:-8}" 3 60 8)"
	if [ -f "$DATADIR/power_switch" ] && [ ! -f "$OFF_FLAG" ]; then
		echo "$maintain" >"$DATADIR/loop_sleep" 2>/dev/null
	else
		echo "$normal" >"$DATADIR/loop_sleep" 2>/dev/null
	fi
}
