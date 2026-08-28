#!/system/bin/sh
# 省电：自适应轮询间隔 + 未插电快路径判定
# 设计目标：不插电时把主循环从「每 3 秒 fork 一次 qsc_switch」降到
# 「每 N 秒读一个 online 文件」，且全程不产生子进程。

QSC_PS_CONF_LOADED=0

# 仅在用户开启 debug_on 时落盘；默认路径不增加日志写入。
qsc_ps_dbg() {
	qsc_debug_enabled || return 0
	qsc_log_once "$@"
}

qsc_ps_record_wake() {
	qsc_debug_enabled || return 0
	printf '%s\n' "$1" >"$DATADIR/qscd_last_wake_reason" 2>/dev/null
}

# 无 fork 读取单行文件；成功置 QSC_PS_VAL
qsc_ps_read() {
	QSC_PS_VAL=""
	[ -r "$1" ] || return 1
	# sysfs 单行节点：read 内建即可，read 失败但已读到内容也算成功
	IFS= read -r QSC_PS_VAL <"$1" 2>/dev/null
	[ -n "$QSC_PS_VAL" ]
}

# 仅在 config.conf 变化时重新解析（内建循环，无 fork）。
# 判断「变过没有」用内建 test -nt 比哨兵文件：原先的 stat 走命令替换，
# 未插电快路径里这是每轮唯一固定的两个 fork（每小时约 240 次白唤醒 CPU）。
qsc_ps_load_conf() {
	local seen="$DATADIR/.conf_seen"
	if [ "$QSC_PS_CONF_LOADED" = "1" ] && [ -f "$seen" ] \
		&& [ ! "$CONF" -nt "$seen" ]; then
		return 0
	fi

	QSC_PS_ENABLE=1
	QSC_PS_IDLE=30
	QSC_PS_IDLE_NATIVE=120
	QSC_PS_PLUGGED=10
	QSC_PS_PLUGGED_NATIVE=60
	# 101 / 999 = 该项不参与 watch 的判断
	QSC_PS_STOP=101
	QSC_PS_TEMP_ON=1
	QSC_PS_TEMP_STOP=999
	QSC_PS_NEAR=3
	QSC_PS_LOOP=3
	QSC_PS_MAINTAIN=8
	QSC_PS_NATIVE=1

	QSC_PS_CONF_LOADED=1
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
			loop_interval_idle_native_sec) QSC_PS_IDLE_NATIVE="$v" ;;
			loop_interval_plugged_sec) QSC_PS_PLUGGED="$v" ;;
			loop_interval_plugged_native_sec) QSC_PS_PLUGGED_NATIVE="$v" ;;
			power_stop) QSC_PS_STOP="$v" ;;
			temperature_switch) QSC_PS_TEMP_ON="$v" ;;
			temperature_switch_stop) QSC_PS_TEMP_STOP="$v" ;;
			loop_interval_near_window) QSC_PS_NEAR="$v" ;;
			loop_interval_sec) QSC_PS_LOOP="$v" ;;
			loop_interval_maintain_sec) QSC_PS_MAINTAIN="$v" ;;
			native_daemon) QSC_PS_NATIVE="$v" ;;
		esac
	done <"$CONF"

	QSC_PS_ENABLE="$(qsc_clamp_int "$QSC_PS_ENABLE" 0 1 1)"
	QSC_PS_IDLE="$(qsc_clamp_int "$QSC_PS_IDLE" 3 300 30)"
	QSC_PS_IDLE_NATIVE="$(qsc_clamp_int "$QSC_PS_IDLE_NATIVE" 0 300 120)"
	QSC_PS_PLUGGED="$(qsc_clamp_int "$QSC_PS_PLUGGED" 2 120 10)"
	QSC_PS_PLUGGED_NATIVE="$(qsc_clamp_int "$QSC_PS_PLUGGED_NATIVE" 0 300 60)"
	# 停充阈值只做形状校验：>100 是「关闭电量停充」的既有约定，原样传给 watch
	QSC_PS_STOP="$(qsc_clamp_int "$QSC_PS_STOP" 1 255 101)"
	QSC_PS_TEMP_ON="$(qsc_clamp_int "$QSC_PS_TEMP_ON" 0 1 1)"
	QSC_PS_TEMP_STOP="$(qsc_clamp_int "$QSC_PS_TEMP_STOP" 25 70 60)"
	[ "$QSC_PS_TEMP_ON" = "1" ] || QSC_PS_TEMP_STOP=999
	QSC_PS_NEAR="$(qsc_clamp_int "$QSC_PS_NEAR" 1 20 3)"
	QSC_PS_LOOP="$(qsc_clamp_int "$QSC_PS_LOOP" 2 60 3)"
	QSC_PS_MAINTAIN="$(qsc_clamp_int "$QSC_PS_MAINTAIN" 3 60 8)"
	QSC_PS_NATIVE="$(qsc_clamp_int "$QSC_PS_NATIVE" 0 1 1)"

	# 只在配置真的更新过时刷哨兵：否则每个 qsc_switch.sh 进程都会写一次，
	# 插电时就变成每轮一次无谓写盘
	if [ ! -f "$seen" ] || [ "$CONF" -nt "$seen" ]; then
		: >"$seen" 2>/dev/null
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
qsc_ps_plugged() {
	local p v
	for p in "$PSDIR/usb/online" \
		"$PSDIR/qc_usb/online" \
		"$PSDIR/ac/online" \
		"$PSDIR/dc/online" \
		"$PSDIR/wireless/online"; do
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			qsc_ps_dbg ps_online debug "插电信号: $p=1"
			return 0
		fi
	done
	# K90U / MCA 停充时 online 可能被驱动压成 0，不能因此跳过整轮。
	for p in "$PSDIR/usb/present" "$PSDIR/qc_usb/present" \
		"$PSDIR/wireless/present" "$PSDIR/ac/present"; do
		if qsc_ps_read "$p" && [ "$QSC_PS_VAL" = "1" ]; then
			qsc_ps_dbg ps_present debug "插电信号: $p=1（online 可能为 0）"
			return 0
		fi
	done
	for p in "$PSDIR/usb/real_type" "$PSDIR/usb/type"; do
		if qsc_ps_read "$p"; then
			v="$QSC_PS_VAL"
			case "$v" in
				""|Unknown|UNKNOWN|None|NONE) ;;
				*)
					qsc_ps_dbg ps_type debug "插电信号: $p=$v（online 可能为 0）"
					return 0
					;;
			esac
		fi
	done
	if qsc_ps_read "$PSDIR/usb/voltage_now"; then
		v="$QSC_PS_VAL"
		case "$v" in
			""|*[!0-9]*) ;;
			*)
				# 单位可能是 µV 或 mV，取 3V 作门槛。
				if [ "$v" -gt 3000000 ] 2>/dev/null || \
					{ [ "$v" -gt 3000 ] 2>/dev/null && [ "$v" -lt 100000 ] 2>/dev/null; }; then
					qsc_ps_dbg ps_voltage debug "插电信号: usb/voltage_now=$v（online 可能为 0）"
					return 0
				fi
				;;
		esac
	fi
	# MCA 的 battery/status 常为 Not charging，但此时仍是插线状态。
	if qsc_ps_read "$PSDIR/battery/status"; then
		case "$QSC_PS_VAL" in
			Charging|Full|"Not charging")
				qsc_ps_dbg ps_status debug "插电信号: battery/status=$QSC_PS_VAL（MCA 兼容）"
				return 0
				;;
		esac
	fi
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

# 省电路径下的简介刷新。
# 跳过整轮时 qsc_switch.sh 不会跑，而简介只在满轮里刷新，未插电时最长要等
# QSC_PS_FULL_MAX_GAP 才动一次，管理器里看着像电量/温度卡住了。
# 这里只用内建 read 取两个 sysfs 值，且仅在显示值变化时才真正改写 module.prop。
# 温度待机时会在两三度间来回抖，只靠「值变了就写」会变成每 30 秒改一次 prop，
# 所以再压一道最小间隔：省电的关键是别唤醒 CPU、别乱写盘，这一路两样都要守住。
QSC_PS_DESC_SIG=""
QSC_PS_DESC_TS=0
QSC_PS_DESC_MIN_GAP=30

# 参数: 当前单调秒（service.sh 已经读过 /proc/uptime，不再重复读）
qsc_ps_refresh_desc() {
	local now="${1:-0}"
	local lv temp digits off plugged stopped sig p
	type qsc_refresh_module_description >/dev/null 2>&1 || return 0
	if [ "$now" -gt 0 ] 2>/dev/null \
		&& [ "$((now - QSC_PS_DESC_TS))" -lt "$QSC_PS_DESC_MIN_GAP" ] 2>/dev/null; then
		return 0
	fi

	lv=""
	for p in "$PSDIR/battery/capacity" \
		"$PSDIR/bms/capacity" \
		"$PSDIR/battery/soc"; do
		if qsc_ps_read "$p"; then
			case "$QSC_PS_VAL" in
				*[!0-9]*) ;;
				*) lv="$QSC_PS_VAL"; break ;;
			esac
		fi
	done

	temp=""
	for p in "$PSDIR/battery/temp" \
		"$PSDIR/bms/temp" \
		"$PSDIR/battery/batt_temp"; do
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

	# 总开关也进指纹：关掉后最迟下一次刷新就显示「已关闭」，不用等满轮
	off=0
	if [ -f "$OFF_FLAG" ] || [ -f "$MODDIR/disable" ]; then
		off=1
	fi
	plugged=0
	qsc_ps_plugged && plugged=1
	stopped=0
	[ -f "$DATADIR/power_switch" ] && stopped=1

	sig="${off}:${plugged}:${stopped}:${lv}:${temp}"
	[ "$sig" = "$QSC_PS_DESC_SIG" ] && return 0
	QSC_PS_DESC_SIG="$sig"
	QSC_PS_DESC_TS="$now"

	# 该函数也由 service.sh 在满轮前调用，不能假定一定是未插电。
	battery_level="$lv"
	temperature="$temp"
	battery_powered=""
	[ "$plugged" = "1" ] && battery_powered="powered: true"
	qsc_refresh_module_description
}

# 等待下一轮。native_daemon=1 且存在 bin/qscd 时交给它阻塞在内核
# power_supply uevent 上：插拔可立即返回，期间不产生定时唤醒；
# 开关关闭或缺少该二进制则退化为 sleep。
# 约定：qscd wait-event <最长秒> <最短秒> → 0=有事件或到时；非 0=不可用（此后改用 sleep）
# 最短秒是为了压掉充电时的 uevent 风暴，避免主循环被事件催成高频空转。
QSC_PS_WAIT_HELPER_OK=1
QSC_PS_WAIT_FLOOR=3

# 守护此刻是否真能用。
# 失败要落一个标记文件：qsc_switch.sh 是另一个进程，看不到主循环里的
# QSC_PS_WAIT_HELPER_OK，否则它会照着「有守护」算出放大后的间隔，
# 而主循环其实已经退回 sleep，插电就要等满那个大间隔才被发现。
# 标记在 service.sh 启动时清掉，换二进制后重新判定。
qsc_ps_native_ready() {
	[ "$QSC_PS_WAIT_HELPER_OK" = "1" ] || return 1
	[ "${QSC_PS_NATIVE:-1}" = "1" ] || return 1
	[ -x "$BINDIR/qscd" ] || return 1
	[ -f "$DATADIR/qscd_unusable" ] && return 1
	return 0
}

# 未插电该睡多久，结果写入 QSC_PS_IDLE_EFF。
# 有守护时可以睡得更久：插电由 uevent 立刻叫醒，等待间隔不再决定响应速度，
# 而它恰好是待机功耗的主要旋钮。没有守护则必须沿用 loop_interval_idle_sec，
# 否则插上充电器要等满一个间隔才被发现。
qsc_ps_idle_secs() {
	QSC_PS_IDLE_EFF="${QSC_PS_IDLE:-30}"
	qsc_ps_native_ready || return 0
	[ "${QSC_PS_IDLE_NATIVE:-0}" -gt "$QSC_PS_IDLE_EFF" ] 2>/dev/null \
		&& QSC_PS_IDLE_EFF="$QSC_PS_IDLE_NATIVE"
	return 0
}

# 守护是否支持 watch（带阈值的等待）。每个进程只问一次；
# C 版不认 features 子命令会退出 2，即视为不支持，自动沿用 wait-event。
# 守护支持哪些扩展子命令。C 版不认 features（退出 2），输出为空即视为
# 无扩展能力，一切自动沿用老路径。
# 结论缓存到 data/qscd_features：qsc_switch.sh 是另一个进程，让它也能只读文件
# 而不必再 fork 一次二进制（换二进制或重启服务时清掉重新问）。
QSC_NATIVE_FEATURES=""

qsc_native_has() {
	local want="$1"
	if [ -z "$QSC_NATIVE_FEATURES" ]; then
		QSC_NATIVE_FEATURES="$(cat "$DATADIR/qscd_features" 2>/dev/null | tr -d '\r\n')"
	fi
	if [ -z "$QSC_NATIVE_FEATURES" ]; then
		[ -x "$BINDIR/qscd" ] || return 1
		QSC_NATIVE_FEATURES="$("$BINDIR/qscd" features 2>/dev/null | tr -d '\r\n')"
		# 用 "-" 占位，免得每轮都去 fork 一次问同一个答案
		[ -n "$QSC_NATIVE_FEATURES" ] || QSC_NATIVE_FEATURES="-"
		echo "$QSC_NATIVE_FEATURES" >"$DATADIR/qscd_features" 2>/dev/null
	fi
	case " $QSC_NATIVE_FEATURES " in
		*" $want "*) return 0 ;;
	esac
	return 1
}

qsc_ps_watch_supported() {
	qsc_native_has watch
}

# 交给守护等待。支持 watch 时把阈值一起交下去：充电中「离阈值还远」的
# uevent 由它自己吞掉，不再每轮叫醒 shell；插拔与跨阈值仍立即返回。
# 未插电或正在维持停充时不传阈值 —— 那两种场景任何电池事件都该让 shell 复算。
qsc_ps_native_wait() {
	local secs="$1" floor="$2" rc
	if qsc_ps_watch_supported; then
		if [ ! -f "$DATADIR/power_switch" ] && qsc_ps_plugged; then
			"$BINDIR/qscd" watch --max "$secs" --floor "$floor" \
				--stop "${QSC_PS_STOP:-101}" --near "${QSC_PS_NEAR:-3}" \
				--temp-stop "${QSC_PS_TEMP_STOP:-999}" >/dev/null 2>&1
			rc="$?"
		else
			"$BINDIR/qscd" watch --max "$secs" --floor "$floor" >/dev/null 2>&1
			rc="$?"
		fi
		[ "$rc" -eq 0 ] && qsc_ps_record_wake "正常返回（事件或截止时间）"
		return "$rc"
	fi
	"$BINDIR/qscd" wait-event "$secs" "$floor" >/dev/null 2>&1
	rc="$?"
	[ "$rc" -eq 0 ] && qsc_ps_record_wake "正常返回（事件或截止时间）"
	return "$rc"
}

qsc_ps_wait() {
	local secs="${1:-30}" floor
	floor="${QSC_PS_WAIT_FLOOR:-3}"
	[ "$secs" -lt "$floor" ] 2>/dev/null && floor="$secs"
	if qsc_ps_native_ready; then
		if qsc_ps_native_wait "$secs" "$floor"; then
			return 0
		fi
		QSC_PS_WAIT_HELPER_OK=0
		: >"$DATADIR/qscd_unusable" 2>/dev/null
		qsc_log_once qscd warn "事件等待器不可用，已退回定时轮询"
		qsc_ps_record_wake "守护不可用，已退回定时轮询"
	fi
	sleep "$secs"
}

# 本轮结束后应睡多久
# 参数: 电量 停充电量 是否插电(1/0) [温度 停充温度]
qsc_ps_next_sleep() {
	local level="$1" stop="$2" plugged="$3" temp="$4" temp_stop="$5" _pl
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
		qsc_ps_idle_secs
		echo "$QSC_PS_IDLE_EFF"
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

	# 插电但离阈值还远。守护支持 watch 时可以睡久些：这段的 uevent 由它
	# 自己按阈值过滤，跨阈值与插拔仍会立刻返回，间隔只是兜底上限。
	_pl="${QSC_PS_PLUGGED:-10}"
	if [ "${QSC_PS_PLUGGED_NATIVE:-0}" -gt "$_pl" ] 2>/dev/null \
		&& qsc_ps_native_ready && qsc_ps_watch_supported; then
		_pl="$QSC_PS_PLUGGED_NATIVE"
	fi
	echo "$_pl"
}
