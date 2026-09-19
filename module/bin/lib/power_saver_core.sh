#!/system/bin/sh
# power_saver: conf / logging helpers
# 省电：自适应轮询间隔 + 未插电快路径判定
# 设计目标：不插电时把主循环从「每 3 秒 fork 一次 qsc_switch」降到
# 「每 N 秒读一个 online 文件」，且全程不产生子进程。

QSC_PS_CONF_LOADED=0
QSC_PS_WAKE_COUNT=0
QSC_PS_LAST_WAKE_REASON=""
QSC_PS_WAIT_FAILURES=0
QSC_PS_WAIT_NEXT_RETRY=0
QSC_PS_NATIVE_MODE=""
QSC_PS_DESC_WRITES=0

# 仅在用户开启 debug_on 时落盘；默认路径不增加日志写入。
qsc_ps_dbg() {
	qsc_debug_enabled || return 0
	qsc_log_once "$@"
}

qsc_ps_native_impl_label() {
	case "$(cat "$DATADIR/native_impl_used" 2>/dev/null | tr -d ' \r\n')" in
		c|C) echo "C" ;;
		rust|Rust) echo "Rust" ;;
		*) echo "未知" ;;
	esac
}

# 服务启动时写一条 INFO，WebUI 日志页默认可见。
qsc_ps_log_startup() {
	local mode impl
	if [ ! -x "$BINDIR/qscd" ]; then
		qsc_log info "事件等待器未安装，主循环使用定时轮询"
		return 0
	fi
	impl="$(qsc_ps_native_impl_label)"
	mode="wait-event"
	qsc_ps_watch_supported && mode="watch"
	qsc_log info "事件等待器已启用（${impl} 版，${mode}）"
}

qsc_ps_native_parse_stderr() {
	local file="$1"
	QSC_PS_NATIVE_WAKE=""
	QSC_PS_NATIVE_ERROR=""
	[ -n "$file" ] && [ -f "$file" ] || return 0
	QSC_PS_NATIVE_WAKE="$(awk -F= '/wake=/{print $2; exit}' "$file" 2>/dev/null | tr -d ' \r\n')"
	QSC_PS_NATIVE_ERROR="$(awk -F= '/reason=/{print $2; exit}' "$file" 2>/dev/null | tr -d ' \r\n')"
}

qsc_ps_log_native_wake() {
	local wake="${QSC_PS_NATIVE_WAKE:-ok}"
	local mode="${QSC_PS_NATIVE_MODE:-wait}"
	local human="" msg _now _prev_at _prev_why
	case "$wake" in
		event|ok) human="收到供电变化，开始检查" ;;
		timeout) human="等待超时，按计划检查" ;;
		*) human="被叫醒（原因：$wake）" ;;
	esac
	msg="${mode}: ${human}"
	qsc_ps_record_wake "${mode}: ${wake}"
	# 唤醒细节走 DEBUG，且做简单节流：同一原因连续刷时最多 30 秒写一条
	qsc_debug_enabled || return 0
	_now="$(date +%s 2>/dev/null)"
	case "$_now" in ""|*[!0-9]*) _now=0 ;; esac
	_prev_at="$(cat "$DATADIR/qscd_wake_log_at" 2>/dev/null | tr -d ' \r\n')"
	_prev_why="$(cat "$DATADIR/qscd_wake_log_why" 2>/dev/null | tr -d '\r\n')"
	case "$_prev_at" in ""|*[!0-9]*) _prev_at=0 ;; esac
	if [ "$wake" = "$_prev_why" ] && [ "$((_now - _prev_at))" -lt 30 ] 2>/dev/null; then
		return 0
	fi
	printf '%s\n' "$_now" >"$DATADIR/qscd_wake_log_at" 2>/dev/null
	printf '%s\n' "$wake" >"$DATADIR/qscd_wake_log_why" 2>/dev/null
	qsc_log debug "qscd ${msg}"
}

qsc_ps_record_wake() {
	QSC_PS_WAKE_COUNT=$((QSC_PS_WAKE_COUNT + 1))
	QSC_PS_LAST_WAKE_REASON="$1"
}

# 无 fork 读取单行文件；成功置 QSC_PS_VAL
qsc_ps_read() {
	QSC_PS_VAL=""
	[ -r "$1" ] || return 1
	# sysfs 单行节点：read 内建即可，read 失败但已读到内容也算成功
	IFS= read -r QSC_PS_VAL <"$1" 2>/dev/null
	[ -n "$QSC_PS_VAL" ]
}

# 解析 power.conf（省电键）+ config.conf（停充/温控阈值，供 watch 使用）
# 哨兵：.power_conf_seen / .conf_seen（阈值变化也要重载）
qsc_ps_load_conf() {
	local seen_p="$DATADIR/.power_conf_seen"
	local seen_c="$DATADIR/.conf_seen"
	local power="${POWER_CONF:-$CONFDIR/power.conf}"
	local conf="${CONF:-}"
	local line k v
	local need=0

	if [ "$QSC_PS_CONF_LOADED" != "1" ]; then
		need=1
	elif [ -f "$power" ] && [ -f "$seen_p" ] && [ "$power" -nt "$seen_p" ]; then
		need=1
	elif [ -f "$conf" ] && [ -f "$seen_c" ] && [ "$conf" -nt "$seen_c" ]; then
		need=1
	elif [ -f "$power" ] && [ ! -f "$seen_p" ]; then
		need=1
	elif [ -f "$conf" ] && [ ! -f "$seen_c" ]; then
		need=1
	fi
	[ "$need" = "1" ] || return 0

	QSC_PS_ENABLE=1
	QSC_PS_IDLE=90
	QSC_PS_IDLE_NATIVE=600
	QSC_PS_PLUGGED=15
	QSC_PS_PLUGGED_NATIVE=90
	QSC_PS_STOP=101
	QSC_PS_TEMP_ON=1
	QSC_PS_TEMP_STOP=999
	QSC_PS_NEAR=3
	QSC_PS_LOOP=3
	QSC_PS_MAINTAIN=30
	QSC_PS_NATIVE=1
	QSC_PS_PROFILE=balanced
	QSC_PS_SCREEN_OFF_SAVER=1
	QSC_PS_NIGHT_SAVER=0
	QSC_PS_DEEP_ENABLE=1
	QSC_PS_DEEP_AFTER=600
	QSC_PS_DEEP_IDLE=900
	QSC_PS_DEEP_FULL_GAP=7200
	QSC_PS_HB_SEC=180
	QSC_PS_SCREEN_DUMPSYS=0
	QSC_PS_IDLE_NATIVE_SET=0
	QSC_PS_HB_SET=0
	QSC_PS_FULL_MAX_GAP=1800

	QSC_PS_CONF_LOADED=1

	# 1) power.conf
	if [ -f "$power" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			case "$line" in
				\#*|"") continue ;;
				*=*) ;;
				*) continue ;;
			esac
			k="${line%%=*}"
			v="${line#*=}"
			case "$k" in
				power_saver) QSC_PS_ENABLE="$v" ;;
				power_profile) QSC_PS_PROFILE="$v" ;;
				screen_off_saver) QSC_PS_SCREEN_OFF_SAVER="$v" ;;
				night_saver) QSC_PS_NIGHT_SAVER="$v" ;;
				deep_idle_enable) QSC_PS_DEEP_ENABLE="$v" ;;
				deep_after_sec) QSC_PS_DEEP_AFTER="$v" ;;
				deep_idle_sec) QSC_PS_DEEP_IDLE="$v" ;;
				deep_full_gap_sec) QSC_PS_DEEP_FULL_GAP="$v" ;;
				heartbeat_sec) QSC_PS_HB_SEC="$v"; QSC_PS_HB_SET=1 ;;
				screen_probe_dumpsys) QSC_PS_SCREEN_DUMPSYS="$v" ;;
				loop_interval_idle_sec) QSC_PS_IDLE="$v" ;;
				loop_interval_idle_native_sec) QSC_PS_IDLE_NATIVE="$v"; QSC_PS_IDLE_NATIVE_SET=1 ;;
				loop_interval_plugged_sec) QSC_PS_PLUGGED="$v" ;;
				loop_interval_plugged_native_sec) QSC_PS_PLUGGED_NATIVE="$v" ;;
				loop_interval_near_window) QSC_PS_NEAR="$v" ;;
				loop_interval_sec) QSC_PS_LOOP="$v" ;;
				loop_interval_maintain_sec) QSC_PS_MAINTAIN="$v" ;;
				native_daemon) QSC_PS_NATIVE="$v" ;;
				description_enable) QSCV_description_enable="$v" ;;
				stop_hold_wakelock) QSCV_stop_hold_wakelock="$v" ;;
				native_impl) QSCV_native_impl="$v" ;;
				desc_viewer_pkgs) QSCV_desc_viewer_pkgs="$v" ;;
			esac
		done <"$power"
	fi

	# 2) config.conf：仅阈值（watch 需要）
	if [ -f "$conf" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			case "$line" in
				\#*|"") continue ;;
				*=*) ;;
				*) continue ;;
			esac
			k="${line%%=*}"
			v="${line#*=}"
			case "$k" in
				power_stop) QSC_PS_STOP="$v" ;;
				temperature_switch) QSC_PS_TEMP_ON="$v" ;;
				temperature_switch_stop) QSC_PS_TEMP_STOP="$v" ;;
			esac
		done <"$conf"
	fi

	case "$QSC_PS_PROFILE" in
		balanced|aggressive|custom) ;;
		*) QSC_PS_PROFILE=balanced ;;
	esac

	QSC_PS_ENABLE="$(qsc_clamp_int "$QSC_PS_ENABLE" 0 1 1)"
	QSC_PS_IDLE="$(qsc_clamp_int "$QSC_PS_IDLE" 3 300 90)"
	QSC_PS_IDLE_NATIVE="$(qsc_clamp_int "$QSC_PS_IDLE_NATIVE" 0 900 600)"
	QSC_PS_PLUGGED="$(qsc_clamp_int "$QSC_PS_PLUGGED" 2 120 15)"
	QSC_PS_PLUGGED_NATIVE="$(qsc_clamp_int "$QSC_PS_PLUGGED_NATIVE" 0 300 90)"
	QSC_PS_STOP="$(qsc_clamp_int "$QSC_PS_STOP" 1 255 101)"
	QSC_PS_TEMP_ON="$(qsc_clamp_int "$QSC_PS_TEMP_ON" 0 1 1)"
	QSC_PS_TEMP_STOP="$(qsc_clamp_int "$QSC_PS_TEMP_STOP" 25 70 60)"
	[ "$QSC_PS_TEMP_ON" = "1" ] || QSC_PS_TEMP_STOP=999
	QSC_PS_NEAR="$(qsc_clamp_int "$QSC_PS_NEAR" 1 20 3)"
	QSC_PS_LOOP="$(qsc_clamp_int "$QSC_PS_LOOP" 2 60 3)"
	QSC_PS_MAINTAIN="$(qsc_clamp_int "$QSC_PS_MAINTAIN" 3 600 30)"
	QSC_PS_NATIVE="$(qsc_clamp_int "$QSC_PS_NATIVE" 0 1 1)"
	QSC_PS_SCREEN_OFF_SAVER="$(qsc_clamp_int "$QSC_PS_SCREEN_OFF_SAVER" 0 1 1)"
	QSC_PS_NIGHT_SAVER="$(qsc_clamp_int "$QSC_PS_NIGHT_SAVER" 0 1 0)"
	QSC_PS_DEEP_ENABLE="$(qsc_clamp_int "$QSC_PS_DEEP_ENABLE" 0 1 1)"
	QSC_PS_DEEP_AFTER="$(qsc_clamp_int "$QSC_PS_DEEP_AFTER" 60 7200 600)"
	QSC_PS_DEEP_IDLE="$(qsc_clamp_int "$QSC_PS_DEEP_IDLE" 60 900 900)"
	QSC_PS_DEEP_FULL_GAP="$(qsc_clamp_int "$QSC_PS_DEEP_FULL_GAP" 600 14400 7200)"
	QSC_PS_HB_SEC="$(qsc_clamp_int "$QSC_PS_HB_SEC" 60 900 180)"
	QSC_PS_SCREEN_DUMPSYS="$(qsc_clamp_int "$QSC_PS_SCREEN_DUMPSYS" 0 1 0)"
	QSCV_description_enable="$(qsc_clamp_int "${QSCV_description_enable:-1}" 0 1 1)"
	description_enable="$QSCV_description_enable"

	type qsc_ps_apply_profile_defaults >/dev/null 2>&1 &&
		qsc_ps_apply_profile_defaults

	if [ -f "$power" ]; then
		if [ ! -f "$seen_p" ] || [ "$power" -nt "$seen_p" ]; then
			: >"$seen_p" 2>/dev/null
		fi
	fi
	if [ -f "$conf" ]; then
		if [ ! -f "$seen_c" ] || [ "$conf" -nt "$seen_c" ]; then
			: >"$seen_c" 2>/dev/null
		fi
	fi
	return 0
}

# 单调秒（/proc/uptime 整数部分），避免快路径每轮 fork 一次 date
qsc_ps_now() {
	local up rest
	QSC_PS_NOW=0
	if IFS=' ' read -r up rest </proc/uptime 2>/dev/null; then
		QSC_PS_NOW="${up%%.*}"
	fi
	case "$QSC_PS_NOW" in
		""|*[!0-9]*) QSC_PS_NOW=0 ;;
	esac
}

# 插电判定：只读 power_supply 节点，无 fork
