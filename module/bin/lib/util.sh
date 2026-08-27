#!/system/bin/sh
# 通用小工具：超时读节点、温度归一化、调试步进、配置钳位

# 调试开关：每个进程只判定一次（主循环每轮会问 9 次）
qsc_debug_enabled() {
	if [ -z "$QSC_DEBUG_ON" ]; then
		if [ "${QSC_DEBUG:-0}" = "1" ] || [ -f "$DATADIR/debug_on" ]; then
			QSC_DEBUG_ON=1
		else
			QSC_DEBUG_ON=0
		fi
	fi
	[ "$QSC_DEBUG_ON" = "1" ]
}

# 默认不写盘：主循环每轮 9 次步进日志会带来数十万次/天的小写入。
# 需要排障时 touch data/debug_on（或 export QSC_DEBUG=1）。
qsc_debug_step() {
	qsc_debug_enabled || return 0
	echo "$(date +%F_%T) step$1" >> "$DATADIR/debug.log"
}

# 单行节点快速读取：纯内建，无 fork、不写临时文件。结果放 QSC_NODE_VAL。
# 仅用于 power_supply 等已知不会阻塞的节点；未知节点仍走 qsc_safe_cat。
# 注意：热路径请直接用本函数 + $QSC_NODE_VAL，套 $(...) 会重新引入一次 fork。
qsc_read_node() {
	QSC_NODE_VAL=""
	[ -r "$1" ] || return 1
	IFS= read -r QSC_NODE_VAL <"$1" 2>/dev/null
	[ -n "$QSC_NODE_VAL" ]
}

# 需要在 $(...) 里取值的场合
qsc_cat_node() {
	qsc_read_node "$1" || return 1
	echo "$QSC_NODE_VAL"
}

QSC_CR="$(printf '\r')"

# 一次遍历 config.conf，把白名单键写成 QSCV_<key>（全内建，无 fork）。
# 多行键（power_switch / *_schedule）不在此处理，仍由各自逻辑 grep。
qsc_conf_scan() {
	local line k v
	[ -f "$CONF" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			\#*|"") continue ;;
			*=*) ;;
			*) continue ;;
		esac
		k="${line%%=*}"
		v="${line#*=}"
		# 容忍 Windows 编辑器留下的 CR
		case "$v" in
			*"$QSC_CR") v="${v%"$QSC_CR"}" ;;
		esac
		case "$k" in
			power_stop|power_start|power_stop_time|charge_full|power_reset \
			|Compatibility_mode|Shut_down|loop_interval_sec \
			|loop_interval_maintain_sec|switch_verify_sec|wireless_policy \
			|app_stop|app_stop_list|history_enable|history_interval_sec \
			|temperature_switch|temperature_switch_stop|temperature_switch_start)
				eval "QSCV_$k=\$v"
				;;
		esac
	done <"$CONF"
	return 0
}

# 避免个别 sysfs 读阻塞拖死主循环
qsc_safe_cat() {
	cat "$1" > "$DATADIR/.safe_tmp" 2>/dev/null &
	local _pid=$!
	local _i
	for _i in 1 2; do
		if [ ! -d "/proc/$_pid" ]; then break; fi
		sleep 1
	done
	kill $_pid 2>/dev/null
	cat "$DATADIR/.safe_tmp" 2>/dev/null
}

# dumpsys/sysfs 温度统一到摄氏度整数
qsc_normalize_temperature() {
	local raw digits normalized
	raw="$(echo "$1" | tr -d ' \r\n')"
	case "$raw" in ""|"-"|*[!0-9-]*) return 1 ;; esac
	digits="${raw#-}"
	case "$digits" in ""|*[!0-9]*) return 1 ;; esac
	if [ "$digits" -ge 10000 ]; then
		normalized=$((raw / 1000))
	elif [ "$digits" -ge 1000 ]; then
		normalized=$((raw / 100))
	elif [ "$digits" -ge 100 ]; then
		normalized=$((raw / 10))
	else
		normalized="$raw"
	fi
	[ "$normalized" -ge -20 -a "$normalized" -le 100 ] || return 1
	echo "$normalized"
}

# dumpsys battery 取电量：仅匹配行首 level:，取首条（适配 Android 16 多字段）
qsc_dumpsys_level() {
	echo "$1" | awk '/^[[:space:]]*level:[[:space:]]+/ { print $2; exit }'
}

# 整数钳位：qsc_clamp_int 值 最小 最大 默认
qsc_clamp_int() {
	local v="$1" lo="$2" hi="$3" def="$4"
	case "$v" in
		""|*[!0-9-]*) echo "$def"; return 0 ;;
	esac
	# 拒绝过大位数（防天文数字拖垮算术）
	case "${v#-}" in
		???????????????*) echo "$def"; return 0 ;;
	esac
	if [ "$v" -lt "$lo" ] 2>/dev/null; then
		echo "$lo"
	elif [ "$v" -gt "$hi" ] 2>/dev/null; then
		echo "$hi"
	else
		echo "$v"
	fi
}

# 电量阈值：1–100 或 110=关闭
qsc_clamp_level_or_off() {
	local v="$1" def="${2:-110}"
	case "$v" in
		""|*[!0-9]*) echo "$def"; return 0 ;;
	esac
	if [ "$v" = "110" ]; then
		echo 110
	elif [ "$v" -ge 1 ] 2>/dev/null && [ "$v" -le 100 ] 2>/dev/null; then
		echo "$v"
	else
		echo "$def"
	fi
}

# 运行日志：YYYY-MM-DD_HH:MM:SS [LEVEL] 内容
# LEVEL: info | warn | error | debug
qsc_log() {
	_qsc_log_write "$@" >>"$LOG_FILE"
}

# 覆盖写入（重建 log.log）
qsc_log_new() {
	_qsc_log_write "$@" >"$LOG_FILE"
}

# 仅当 KEY 对应内容变化时写入，避免 3 秒主循环刷屏
qsc_log_once() {
	_qsc_okey="$1"
	_qsc_olvl="$2"
	shift 2
	_qsc_omsg="$*"
	_qsc_of="$DATADIR/.log_once_${_qsc_okey}"
	mkdir -p "$DATADIR" 2>/dev/null
	# 内建 read 比较，避免主循环里每次判重都 fork 一个 cat
	_qsc_oprev=""
	if [ -r "$_qsc_of" ]; then
		IFS= read -r _qsc_oprev <"$_qsc_of" 2>/dev/null
		[ "$_qsc_oprev" = "$_qsc_omsg" ] && return 0
	fi
	printf '%s\n' "$_qsc_omsg" >"$_qsc_of"
	qsc_log "$_qsc_olvl" "$_qsc_omsg"
}

qsc_log_once_clear() {
	rm -f "$DATADIR/.log_once_$1"
}

_qsc_log_write() {
	local lvl="${1:-info}"
	shift
	case "$lvl" in
		info|INFO) lvl=INFO ;;
		warn|WARN) lvl=WARN ;;
		error|ERROR) lvl=ERROR ;;
		debug|DEBUG) lvl=DEBUG ;;
		*) lvl=INFO ;;
	esac
	echo "$(date +%F_%T) [$lvl] $*"
}

# 系统通知：notify_charge_event=1 时发送；失败静默
# $1=tag(qsc_stop|qsc_resume|qsc_fail)  $2=标题  $3=正文
qsc_notify_quiet_now() {
	local range start end line any=0
	[ -f "$CONF" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		range="$(printf '%s' "$line" | sed 's/^notify_quiet_schedule=//;s/^\[//;s/\]$//' | tr -d ' \r\n')"
		[ -n "$range" ] || continue
		any=1
		case "$range" in
			*-*-*) continue ;;
			*-*)
				start="${range%%-*}"
				end="${range#*-}"
				if qsc_time_in_range "$start" "$end"; then
					return 0
				fi
				;;
		esac
	done <<EOF
$(grep '^notify_quiet_schedule=' "$CONF" 2>/dev/null)
EOF
	return 1
}

qsc_notify_kind_allowed() {
	local tag="$1" kinds need
	kinds="$(sed -n 's/^notify_charge_kinds=//p' "$CONF" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	[ -n "$kinds" ] || kinds="stop,resume,fail"
	case "$tag" in
		qsc_stop) need=stop ;;
		qsc_resume) need=resume ;;
		qsc_fail) need=fail ;;
		*) return 0 ;;
	esac
	case ",$kinds," in
		*",$need,"*) return 0 ;;
	esac
	return 1
}

qsc_notify() {
	local tag="$1" title="$2" body="$3" en
	[ -n "$tag" ] && [ -n "$body" ] || return 0
	[ -f "$CONF" ] || return 0
	en="$(sed -n 's/^notify_charge_event=//p' "$CONF" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	[ "$en" = "1" ] || return 0
	qsc_notify_kind_allowed "$tag" || return 0
	# 勿扰时段内不发（失败通知仍发，避免用户错过异常）
	if [ "$tag" != "qsc_fail" ] && qsc_notify_quiet_now; then
		return 0
	fi
	title="${title:-充电控制}"
	tag="$(printf '%s' "$tag" | tr -d "'\"\r\n")"
	title="$(printf '%s' "$title" | tr -d "'\"\r\n")"
	body="$(printf '%s' "$body" | tr -d "'\"\r\n")"
	if command -v su >/dev/null 2>&1; then
		su -lp 2000 -c "cmd notification post -t '$title' '$tag' '$body'" >/dev/null 2>&1 && return 0
	fi
	cmd notification post -t "$title" "$tag" "$body" >/dev/null 2>&1 || true
}

# HH:MM → 当日分钟数（0–1439）；非法返回空
qsc_hm_to_min() {
	local hm="$1" h m
	hm="$(printf '%s' "$hm" | tr -d ' \r\n')"
	case "$hm" in
		[0-1][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9]) ;;
		*) return 1 ;;
	esac
	h="${hm%%:*}"
	m="${hm##*:}"
	h="${h#0}"
	m="${m#0}"
	[ -n "$h" ] || h=0
	[ -n "$m" ] || m=0
	echo $((h * 60 + m))
}

# 当前时刻是否落在 start-end（支持跨天：22:00-08:00）
qsc_time_in_range() {
	local start="$1" end="$2" now_hm now_m start_m end_m
	now_hm="$(date +%H:%M 2>/dev/null)" || return 1
	now_m="$(qsc_hm_to_min "$now_hm")" || return 1
	start_m="$(qsc_hm_to_min "$start")" || return 1
	end_m="$(qsc_hm_to_min "$end")" || return 1
	if [ "$start_m" -le "$end_m" ]; then
		[ "$now_m" -ge "$start_m" ] && [ "$now_m" -lt "$end_m" ]
	else
		[ "$now_m" -ge "$start_m" ] || [ "$now_m" -lt "$end_m" ]
	fi
}

# 电量停充时段：无配置或任一命中 → 0（可生效）；有配置但未命中 → 1
qsc_power_stop_schedule_active() {
	local range start end any=0 line
	[ -f "$CONF" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		range="$(printf '%s' "$line" | sed 's/^power_stop_schedule=//;s/^\[//;s/\]$//' | tr -d ' \r\n')"
		[ -n "$range" ] || continue
		any=1
		case "$range" in
			*-*-*) continue ;;
			*-*)
				start="${range%%-*}"
				end="${range#*-}"
				if qsc_time_in_range "$start" "$end"; then
					return 0
				fi
				;;
		esac
	done <<EOF
$(grep '^power_stop_schedule=' "$CONF" 2>/dev/null)
EOF
	[ "$any" = "0" ] && return 0
	return 1
}

# 兼容旧名
_debug_step() { qsc_debug_step "$@"; }
_safe_cat() { qsc_safe_cat "$@"; }
_normalize_temperature() { qsc_normalize_temperature "$@"; }
