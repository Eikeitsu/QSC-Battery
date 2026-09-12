#!/system/bin/sh
# 通用小工具：超时读节点、温度归一化、调试步进、配置钳位

# 正常由 common.sh 的 qsc_init_paths 设好；这里兜一道底，
# 免得有人直接 source 某个 lib 时把路径拼成 /battery/capacity 这种废路径
PSDIR="${PSDIR:-/sys/class/power_supply}"

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
	qsc_trim_file_bytes "$DATADIR/debug.log" 262144 131072
}

# 按字节裁剪日志：超过 max 时只保留末尾 keep 字节。失败静默。
# 用于 debug.log / 运行日志等会持续追加的文件，避免占满 /data。
qsc_trim_file_bytes() {
	local file="$1" max="$2" keep="$3" size
	[ -f "$file" ] || return 0
	case "$max" in ""|*[!0-9]*) return 0 ;; esac
	case "$keep" in ""|*[!0-9]*) return 0 ;; esac
	size="$(wc -c <"$file" 2>/dev/null | tr -d ' ')"
	case "$size" in ""|*[!0-9]*) return 0 ;; esac
	[ "$size" -gt "$max" ] 2>/dev/null || return 0
	tail -c "$keep" "$file" >"$file.trim.$$" 2>/dev/null &&
		mv -f "$file.trim.$$" "$file" 2>/dev/null
	rm -f "$file.trim.$$" 2>/dev/null
	return 0
}

# 按行数裁剪日志：超过 max 行时只保留末尾 keep 行。
qsc_trim_file_lines() {
	local file="$1" max="$2" keep="$3" n
	[ -f "$file" ] || return 0
	case "$max" in ""|*[!0-9]*) return 0 ;; esac
	case "$keep" in ""|*[!0-9]*) return 0 ;; esac
	n="$(wc -l <"$file" 2>/dev/null | tr -d ' ')"
	case "$n" in ""|*[!0-9]*) return 0 ;; esac
	[ "$n" -gt "$max" ] 2>/dev/null || return 0
	tail -n "$keep" "$file" >"$file.trim.$$" 2>/dev/null &&
		mv -f "$file.trim.$$" "$file" 2>/dev/null
	rm -f "$file.trim.$$" 2>/dev/null
	return 0
}

# 服务启动时清理临时文件，并对可能胀大的调试日志做容量控制。
# 不删 charge_events / charge_history / health_history / log.log：那是用户可见历史。
qsc_boot_cleanup_logs() {
	rm -f "$DATADIR/startup.log" \
		"$DATADIR/service_diag" \
		"$DATADIR"/qscd_wait_error.* \
		"$DATADIR/qscd_unusable.tmp" 2>/dev/null
	# 开关测试日志偶发残留，开机清掉即可（不是充放电历史）
	rm -f "$DATADIR/switch_test.log" \
		"$DATADIR/switch_test_bg.log" \
		"$DATADIR/switch_test_status" 2>/dev/null
	# debug.log：跨重启保留链路，但按 256KiB 封顶，避免 debug_on 忘关撑爆分区
	qsc_trim_file_bytes "$DATADIR/debug.log" 262144 131072
	# 运行日志软上限：超过 400 行留最近 300 行（主循环里还会再裁）
	qsc_trim_file_lines "${LOG_FILE:-$DATADIR/log.log}" 400 300
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

# XP 稀疏日志（与 system_server 同格式 epoch_ms\tLEVEL\tmsg），供 APP/WebUI LSP 页读取
qsc_xp_file_log() {
	local lvl="${1:-INFO}" msg ms
	shift
	msg="$*"
	case "$lvl" in
		info|INFO) lvl=INFO ;;
		warn|WARN) lvl=WARN ;;
		error|ERROR) lvl=ERROR ;;
		debug|DEBUG) lvl=DEBUG ;;
		*) lvl=INFO ;;
	esac
	mkdir -p "$DATADIR" 2>/dev/null || true
	ms="$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")"
	printf '%s\t%s\t%s\n' "$ms" "$lvl" "$msg" >>"$DATADIR/xp.log" 2>/dev/null || true
	# 限制体积
	if [ -f "$DATADIR/xp.log" ]; then
		_xp_sz="$(wc -c <"$DATADIR/xp.log" 2>/dev/null || echo 0)"
		case "$_xp_sz" in ""|*[!0-9]*) _xp_sz=0 ;; esac
		if [ "$_xp_sz" -gt 48000 ] 2>/dev/null; then
			tail -c 24000 "$DATADIR/xp.log" >"$DATADIR/xp.log.tmp" 2>/dev/null &&
				mv -f "$DATADIR/xp.log.tmp" "$DATADIR/xp.log" 2>/dev/null
		fi
	fi
}

# 启动时：预置可写日志落点 + 记录探活（不 cat 全量，避免重启重复；APP 会合并多路径）
qsc_xp_bootstrap_logs() {
	mkdir -p "$DATADIR" 2>/dev/null || true
	touch /data/system/qsc_xp.log /data/local/tmp/qsc_xp.log 2>/dev/null || true
	chmod 666 /data/system/qsc_xp.log /data/local/tmp/qsc_xp.log 2>/dev/null || true
	if [ -f /data/system/qsc_xp_alive ]; then
		qsc_xp_file_log INFO "ok magisk: xp alive present (③ injected)"
	elif [ -f /data/system/qsc_xp_off ]; then
		qsc_xp_file_log WARN "magisk: xp soft-off (/data/system/qsc_xp_off)"
	else
		# 与「作用域检测」无关：仅表示 system_server 未写出存活文件
		qsc_xp_file_log WARN "magisk: xp alive missing (③ not injected — enable module, scope=system, reboot)"
	fi
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

# 取消指定 tag 的通知（失败静默）
qsc_notify_cancel() {
	local tag="$1"
	[ -n "$tag" ] || return 0
	tag="$(printf '%s' "$tag" | tr -d "'\"\r\n")"
	if command -v su >/dev/null 2>&1; then
		su -lp 2000 -c "cmd notification cancel '$tag'" >/dev/null 2>&1 && return 0
	fi
	cmd notification cancel "$tag" >/dev/null 2>&1 || true
}

# 常显功耗通知：把当前电量/温度/电流挂在状态栏，供快速查看待机耗电
# 配置 notify_power_status=1 开启；同文案会节流，避免每轮狂刷。
qsc_notify_power_status() {
	local en level temp ua ma abs_ua body title prev now force="$1"
	local batt_status flow _last
	[ -f "$CONF" ] || return 0
	en="$(sed -n 's/^notify_power_status=//p' "$CONF" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	if [ "$en" != "1" ]; then
		if [ -f "$DATADIR/power_status_notify_on" ]; then
			qsc_notify_cancel qsc_power
			rm -f "$DATADIR/power_status_notify_on" \
				"$DATADIR/power_status_notify_body" \
				"$DATADIR/power_status_notify_at" 2>/dev/null
		fi
		return 0
	fi
	touch "$DATADIR/power_status_notify_on" 2>/dev/null
	level="$(qsc_cat_node "$PSDIR/battery/capacity" 2>/dev/null)"
	[ -z "$level" ] && level="--"
	temp="$(qsc_cat_node "$PSDIR/battery/temp" 2>/dev/null)"
	if [ -n "$temp" ] && type qsc_normalize_temperature >/dev/null 2>&1; then
		temp="$(qsc_normalize_temperature "$temp" 2>/dev/null)" || temp=""
	fi
	[ -z "$temp" ] && temp="--"
	ua="$(qsc_cat_node "$PSDIR/battery/current_now" 2>/dev/null)"
	uv="$(qsc_cat_node "$PSDIR/battery/voltage_now" 2>/dev/null)"
	batt_status="$(qsc_cat_node "$PSDIR/battery/status" 2>/dev/null)"
	case "$ua" in
		""|*[!0-9-]*) ma="--" ;;
		*)
			abs_ua="${ua#-}"
			case "$abs_ua" in ""|*[!0-9]*) ma="--" ;;
				*) ma=$((abs_ua / 1000)) ;;
			esac
			;;
	esac
	# 瞬时功耗估算：P(W) ≈ |I(µA)| × V(µV) / 1e12；无电压节点时仅显示 mA
	watts="--"
	case "$uv" in
		""|*[!0-9]*) ;;
		*)
			if [ "$ma" != "--" ]; then
				abs_uv="$uv"
				# mW = mA × mV / 1000
				_mv=$((abs_uv / 1000))
				_mw=$((ma * _mv / 1000))
				_w=$((_mw / 1000))
				_frac=$(((_mw % 1000) / 10))
				case "$_frac" in
					[0-9]) _frac="0${_frac}" ;;
				esac
				watts="${_w}.${_frac}W"
			fi
			;;
	esac
	if [ -f "$DATADIR/power_switch" ]; then
		flow="已停充"
	else
		case "$batt_status" in
			Charging|Full) flow="充电中" ;;
			Discharging) flow="放电中" ;;
			"Not charging") flow="未在充电" ;;
			*)
				if [ "$ma" != "--" ] && [ "$ua" != "${ua#-}" ]; then
					flow="放电中"
				elif [ "$ma" != "--" ]; then
					flow="充电中"
				else
					flow="监测中"
				fi
				;;
		esac
	fi
	if [ "$ma" = "--" ]; then
		body="电量 ${level}% · ${temp}°C · ${flow}"
	elif [ "$watts" = "--" ]; then
		body="电量 ${level}% · ${temp}°C · ${flow} ${ma}mA"
	else
		body="电量 ${level}% · ${temp}°C · ${flow} ${ma}mA · ${watts}"
	fi
	title="电池功耗"
	prev="$(cat "$DATADIR/power_status_notify_body" 2>/dev/null | tr -d '\r\n')"
	now="$(date +%s 2>/dev/null)"
	case "$now" in ""|*[!0-9]*) now=0 ;; esac
	if [ "$force" != "1" ] && [ "$body" = "$prev" ]; then
		_last="$(cat "$DATADIR/power_status_notify_at" 2>/dev/null | tr -d ' \r\n')"
		case "$_last" in ""|*[!0-9]*) _last=0 ;; esac
		# 文案未变时最多 60 秒刷新一次，防止系统吞掉常驻通知
		[ "$((now - _last))" -lt 60 ] 2>/dev/null && return 0
	fi
	printf '%s\n' "$body" >"$DATADIR/power_status_notify_body" 2>/dev/null
	printf '%s\n' "$now" >"$DATADIR/power_status_notify_at" 2>/dev/null
	title="$(printf '%s' "$title" | tr -d "'\"\r\n")"
	body="$(printf '%s' "$body" | tr -d "'\"\r\n")"
	if command -v su >/dev/null 2>&1; then
		su -lp 2000 -c "cmd notification post -t '$title' 'qsc_power' '$body'" >/dev/null 2>&1 && return 0
	fi
	cmd notification post -t "$title" "qsc_power" "$body" >/dev/null 2>&1 || true
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
