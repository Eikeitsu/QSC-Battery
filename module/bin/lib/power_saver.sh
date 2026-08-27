#!/system/bin/sh
# 省电：自适应轮询间隔 + 未插电快路径判定
# 设计目标：不插电时把主循环从「每 3 秒 fork 一次 qsc_switch」降到
# 「每 N 秒读一个 online 文件」，且全程不产生子进程。

QSC_PS_CONF_MTIME=""

# 无 fork 读取单行文件；成功置 QSC_PS_VAL
qsc_ps_read() {
	QSC_PS_VAL=""
	[ -r "$1" ] || return 1
	# sysfs 单行节点：read 内建即可，read 失败但已读到内容也算成功
	IFS= read -r QSC_PS_VAL <"$1" 2>/dev/null
	[ -n "$QSC_PS_VAL" ]
}

# 仅在 config.conf 变化时重新解析（内建循环，无 fork）
qsc_ps_load_conf() {
	local mtime
	mtime="$(qsc_ps_conf_mtime)"
	if [ -n "$mtime" ] && [ "$mtime" = "$QSC_PS_CONF_MTIME" ]; then
		return 0
	fi
	QSC_PS_CONF_MTIME="$mtime"

	QSC_PS_ENABLE=1
	QSC_PS_IDLE=30
	QSC_PS_PLUGGED=10
	QSC_PS_NEAR=3
	QSC_PS_LOOP=3
	QSC_PS_MAINTAIN=8
	QSC_PS_NATIVE=1

	[ -f "$CONF" ] || return 0
	local line k v
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
			loop_interval_idle_sec) QSC_PS_IDLE="$v" ;;
			loop_interval_plugged_sec) QSC_PS_PLUGGED="$v" ;;
			loop_interval_near_window) QSC_PS_NEAR="$v" ;;
			loop_interval_sec) QSC_PS_LOOP="$v" ;;
			loop_interval_maintain_sec) QSC_PS_MAINTAIN="$v" ;;
			native_daemon) QSC_PS_NATIVE="$v" ;;
		esac
	done <"$CONF"

	QSC_PS_ENABLE="$(qsc_clamp_int "$QSC_PS_ENABLE" 0 1 1)"
	QSC_PS_IDLE="$(qsc_clamp_int "$QSC_PS_IDLE" 3 300 30)"
	QSC_PS_PLUGGED="$(qsc_clamp_int "$QSC_PS_PLUGGED" 2 120 10)"
	QSC_PS_NEAR="$(qsc_clamp_int "$QSC_PS_NEAR" 1 20 3)"
	QSC_PS_LOOP="$(qsc_clamp_int "$QSC_PS_LOOP" 2 60 3)"
	QSC_PS_MAINTAIN="$(qsc_clamp_int "$QSC_PS_MAINTAIN" 3 60 8)"
	QSC_PS_NATIVE="$(qsc_clamp_int "$QSC_PS_NATIVE" 0 1 1)"
	return 0
}

qsc_ps_conf_mtime() {
	[ -f "$CONF" ] || return 0
	stat -c %Y "$CONF" 2>/dev/null || echo ""
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

# 插电判定：只读 online 节点，无 fork
qsc_ps_plugged() {
	local p
	for p in /sys/class/power_supply/usb/online \
		/sys/class/power_supply/qc_usb/online \
		/sys/class/power_supply/ac/online \
		/sys/class/power_supply/dc/online \
		/sys/class/power_supply/wireless/online; do
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			return 0
		fi
	done
	return 1
}

# 未插电且无停充维持时可跳过整轮；仍按 QSC_PS_FULL_MAX_GAP 定期跑满轮，
# 保证曲线采样、简介刷新、配置纠正不会长期停摆。
QSC_PS_FULL_MAX_GAP=300

qsc_ps_can_skip_round() {
	local now last
	[ "${QSC_PS_ENABLE:-1}" = "1" ] || return 1
	# 模块关闭时也别空转，但仍要走满轮以刷新简介
	[ -f "$DATADIR/power_switch" ] && return 1
	qsc_ps_plugged && return 1

	now="${1:-0}"
	last="${QSC_PS_LAST_FULL:-0}"
	if [ "$now" -gt 0 ] 2>/dev/null && [ "$((now - last))" -ge "$QSC_PS_FULL_MAX_GAP" ] 2>/dev/null; then
		return 1
	fi
	return 0
}

# 省电快路径下的简介刷新。
# 跳过整轮时 qsc_switch.sh 不会跑，而简介只在满轮里刷新，未插电时最长要等
# QSC_PS_FULL_MAX_GAP 才动一次，管理器里看着像电量/温度卡住了。
# 这里只用内建 read 取两个 sysfs 值，且仅在显示值变化时才真正改写 module.prop，
# 未插电时电量/温度变化很慢，实际写盘次数很少。
QSC_PS_DESC_SIG=""

qsc_ps_refresh_desc() {
	local lv temp digits off sig p
	type qsc_refresh_module_description >/dev/null 2>&1 || return 0

	lv=""
	for p in /sys/class/power_supply/battery/capacity \
		/sys/class/power_supply/bms/capacity \
		/sys/class/power_supply/battery/soc; do
		if qsc_ps_read "$p"; then
			case "$QSC_PS_VAL" in
				*[!0-9]*) ;;
				*) lv="$QSC_PS_VAL"; break ;;
			esac
		fi
	done

	temp=""
	for p in /sys/class/power_supply/battery/temp \
		/sys/class/power_supply/bms/temp \
		/sys/class/power_supply/battery/batt_temp; do
		qsc_ps_read "$p" && { temp="$QSC_PS_VAL"; break; }
	done
	if [ -n "$temp" ]; then
		# 与 qsc_normalize_temperature 同一套换算，但走内建算术以免每轮 fork
		case "$temp" in
			""|"-"|*[!0-9-]*) temp="" ;;
			*)
				digits="${temp#-}"
				case "$digits" in
					""|*[!0-9]*) temp="" ;;
					*)
						if [ "$digits" -ge 10000 ]; then
							temp=$((temp / 1000))
						elif [ "$digits" -ge 1000 ]; then
							temp=$((temp / 100))
						elif [ "$digits" -ge 100 ]; then
							temp=$((temp / 10))
						fi
						[ "$temp" -ge -20 ] && [ "$temp" -le 100 ] || temp=""
						;;
				esac
				;;
		esac
	fi

	# 总开关也进指纹：关掉后要马上显示「已关闭」，不能等满轮
	off=0
	if [ -f "$OFF_FLAG" ] || [ -f "$MODDIR/disable" ]; then
		off=1
	fi

	sig="${off}:${lv}:${temp}"
	[ "$sig" = "$QSC_PS_DESC_SIG" ] && return 0
	QSC_PS_DESC_SIG="$sig"

	# 快路径只在未插电且未维持停充时进入，简介必然走「未充电」分支
	battery_level="$lv"
	temperature="$temp"
	battery_powered=""
	qsc_refresh_module_description
}

# 等待下一轮。native_daemon=1 且存在 bin/qscd 时交给它阻塞在内核
# power_supply uevent 上：插拔可立即返回，期间不产生定时唤醒；
# 开关关闭或缺少该二进制则退化为 sleep。
# 约定：qscd wait-event <最长秒> <最短秒> → 0=有事件或到时；非 0=不可用（此后改用 sleep）
# 最短秒是为了压掉充电时的 uevent 风暴，避免主循环被事件催成高频空转。
QSC_PS_WAIT_HELPER_OK=1
QSC_PS_WAIT_FLOOR=3

qsc_ps_wait() {
	local secs="${1:-30}" floor
	floor="${QSC_PS_WAIT_FLOOR:-3}"
	[ "$secs" -lt "$floor" ] 2>/dev/null && floor="$secs"
	if [ "$QSC_PS_WAIT_HELPER_OK" = "1" ] && [ "${QSC_PS_NATIVE:-1}" = "1" ] \
		&& [ -x "$BINDIR/qscd" ]; then
		if "$BINDIR/qscd" wait-event "$secs" "$floor" >/dev/null 2>&1; then
			return 0
		fi
		QSC_PS_WAIT_HELPER_OK=0
		qsc_log_once qscd warn "事件等待器不可用，已退回定时轮询"
	fi
	sleep "$secs"
}

# 本轮结束后应睡多久
# 参数: 电量 停充电量 是否插电(1/0) [温度 停充温度]
qsc_ps_next_sleep() {
	local level="$1" stop="$2" plugged="$3" temp="$4" temp_stop="$5"
	if [ "${QSC_PS_ENABLE:-1}" != "1" ]; then
		echo "${QSC_PS_LOOP:-3}"
		return 0
	fi
	# 维持停充：按维持间隔
	if [ -f "$DATADIR/power_switch" ] && [ ! -f "$OFF_FLAG" ]; then
		echo "${QSC_PS_MAINTAIN:-8}"
		return 0
	fi
	if [ "$plugged" != "1" ]; then
		echo "${QSC_PS_IDLE:-30}"
		return 0
	fi

	# 插电且接近电量阈值 → 短间隔，保证不冲过阈值
	case "$level$stop" in
		""|*[!0-9]*) echo "${QSC_PS_LOOP:-3}"; return 0 ;;
	esac
	if [ "$stop" -le 100 ] 2>/dev/null \
		&& [ "$((stop - level))" -le "${QSC_PS_NEAR:-3}" ] 2>/dev/null; then
		echo "${QSC_PS_LOOP:-3}"
		return 0
	fi

	# 温度上升比电量快，接近温控阈值时同样收紧间隔
	case "$temp$temp_stop" in
		""|*[!0-9]*) ;;
		*)
			if [ "$((temp_stop - temp))" -le 3 ] 2>/dev/null; then
				echo "${QSC_PS_LOOP:-3}"
				return 0
			fi
			;;
	esac

	echo "${QSC_PS_PLUGGED:-10}"
}
