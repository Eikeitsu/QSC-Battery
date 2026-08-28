#!/system/bin/sh
# 充放电历史采样：data/charge_history.csv（约 24h）

QSC_HISTORY_FILE="${QSC_HISTORY_FILE:-$DATADIR/charge_history.csv}"
QSC_HISTORY_MAX_LINES=1600
QSC_HISTORY_BATCH=5
QSC_HISTORY_BUFFER="${QSC_HISTORY_FILE}.pending"

# 充电来源：usb | wireless | none
qsc_charge_source() {
	local p
	# 内建 read，避免每轮为几个 online 节点各 fork 一次 cat
	for p in "$PSDIR/usb/online" "$PSDIR/qc_usb/online" \
		"$PSDIR/ac/online" "$PSDIR/dc/online"; do
		[ -r "$p" ] || continue
		QSC_SRC_VAL=""
		IFS= read -r QSC_SRC_VAL <"$p" 2>/dev/null
		[ "$QSC_SRC_VAL" = "1" ] && {
			echo usb
			return 0
		}
	done
	for p in "$PSDIR/wireless/online" "$PSDIR/wireless/present" \
		"$PSDIR/wireless_chg/online"; do
		[ -r "$p" ] || continue
		QSC_SRC_VAL=""
		IFS= read -r QSC_SRC_VAL <"$p" 2>/dev/null
		[ "$QSC_SRC_VAL" = "1" ] && {
			echo wireless
			return 0
		}
	done
	echo none
	return 1
}

# $1=包名列表文件（一行一个）命中前台或进程则 0
# 进程那半边优先交给原生守护：它直接遍历 /proc/<pid>/cmdline，
# 省掉 ps -ef 全量快照与逐包两次 grep（按 App 停充最贵的一步）。
# 退出 0=命中、1=确定没命中（可直接跳到前台检测）、其它=不可用则退回 ps。
qsc_pkg_proc_hit() {
	local list_file="$1" pkg snap _rc
	if qsc_native_has pkgs && qsc_ps_native_ready; then
		"$BINDIR/qscd" pkgs "$list_file" >/dev/null 2>&1
		_rc=$?
		[ "$_rc" = "0" ] && return 0
		[ "$_rc" = "1" ] && return 1
		qsc_log_once qscd_pkgs warn "原生进程检测不可用，已退回 ps"
	fi
	# 一次 ps 快照供全部包名匹配：原先每个包名都要跑一遍 ps -ef
	snap="$(ps -ef 2>/dev/null)"
	while IFS= read -r pkg || [ -n "$pkg" ]; do
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
		[ -n "$pkg" ] || continue
		# 命中主进程即算；仅命中 "pkg:xxx" 子进程不算
		if printf '%s\n' "$snap" | grep -F "$pkg" | grep -qv "${pkg}:"; then
			return 0
		fi
	done <"$list_file"
	return 1
}

qsc_pkg_list_hit() {
	local list_file="$1" pkg focus
	[ -f "$list_file" ] && [ -s "$list_file" ] || return 1
	if qsc_pkg_proc_hit "$list_file"; then
		return 0
	fi
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

qsc_history_flush_pending() {
	local n now
	[ -s "$QSC_HISTORY_BUFFER" ] || return 0
	mkdir -p "$DATADIR" 2>/dev/null
	if [ ! -f "$QSC_HISTORY_FILE" ]; then
		echo "ts,level,temp,current_ua,status,source" >"$QSC_HISTORY_FILE"
	fi
	cat "$QSC_HISTORY_BUFFER" >>"$QSC_HISTORY_FILE" 2>/dev/null || return 1
	: >"$QSC_HISTORY_BUFFER"
	n="$(wc -l <"$QSC_HISTORY_FILE" 2>/dev/null | tr -d ' ')"
	case "$n" in ""|*[!0-9]*) n=0 ;; esac
	if [ -n "$n" ] && [ "$n" -gt "$QSC_HISTORY_MAX_LINES" ] 2>/dev/null; then
		{
			head -n 1 "$QSC_HISTORY_FILE"
			tail -n $((QSC_HISTORY_MAX_LINES - 1)) "$QSC_HISTORY_FILE"
		} >"$QSC_HISTORY_FILE.tmp" 2>/dev/null &&
			mv -f "$QSC_HISTORY_FILE.tmp" "$QSC_HISTORY_FILE"
	fi
	now="$(date +%s 2>/dev/null)"
	if [ -n "$now" ]; then
		awk -F, -v cut="$((now - 129600))" 'NR==1 || $1+0>=cut' \
			"$QSC_HISTORY_FILE" >"$QSC_HISTORY_FILE.trim" 2>/dev/null &&
			mv -f "$QSC_HISTORY_FILE.trim" "$QSC_HISTORY_FILE"
	fi
	return 0
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
	[ -n "$level" ] || level="$(qsc_cat_node "$PSDIR/battery/capacity" 2>/dev/null)"
	[ -n "$temp" ] || temp="--"
	src="$(qsc_charge_source 2>/dev/null)"

	# 只在插电期间采样：放电段由 WebUI 现场解析系统 batterystats 历史补齐，
	# 后台因此在日常待机时对本文件零写入。电流线只有插电时才有意义。
	[ "$src" = "none" ] && return 0

	echo "$now" >"$DATADIR/history_last_ts" 2>/dev/null
	cur="$(qsc_cat_node "$PSDIR/battery/current_now" 2>/dev/null)"
	status="$(qsc_cat_node "$PSDIR/battery/status" 2>/dev/null)"
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
	# 先聚合到 pending，五个采样再一次性追加 CSV，避免充电时高频打开主历史文件。
	echo "${now},${level},${temp},${cur},${status},${src}" >>"$QSC_HISTORY_BUFFER"
	n="$(wc -l <"$QSC_HISTORY_BUFFER" 2>/dev/null | tr -d ' ')"
	case "$n" in ""|*[!0-9]*) n=0 ;; esac
	if [ "$n" -lt "$QSC_HISTORY_BATCH" ]; then
		return 0
	fi
	qsc_history_flush_pending
}

# 根据是否停充维持，写入本轮建议 sleep 秒数
qsc_write_loop_sleep() {
	local normal="$1" maintain="$2"
	normal="$(qsc_clamp_int "${normal:-3}" 2 30 3)"
	maintain="$(qsc_clamp_int "${maintain:-8}" 3 60 8)"
	if [ -f "$DATADIR/power_switch" ] && [ ! -f "$OFF_FLAG" ]; then
		qsc_write_loop_sleep_value "$maintain"
	else
		qsc_write_loop_sleep_value "$normal"
	fi
}

# 值未变则不写盘（主循环每轮都写会白白产生数万次/天的小写入）
qsc_write_loop_sleep_value() {
	local v="$1" old
	v="$(qsc_clamp_int "${v:-3}" 2 300 3)"
	old="$(cat "$DATADIR/loop_sleep" 2>/dev/null | tr -d ' \r\n')"
	[ "$old" = "$v" ] && return 0
	echo "$v" >"$DATADIR/loop_sleep" 2>/dev/null
}
