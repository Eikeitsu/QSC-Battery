#!/system/bin/sh
# power_saver: idle / native wait
qsc_ps_native_ready() {
	local now
	[ "${QSC_PS_NATIVE:-1}" = "1" ] || return 1
	[ -x "$BINDIR/qscd" ] || return 1
	if [ "$QSC_PS_WAIT_HELPER_OK" != "1" ]; then
		now="${QSC_PS_NOW:-0}"
		case "$now" in ""|*[!0-9]*) now=0 ;; esac
		[ "$now" -gt 0 ] || qsc_ps_now
		[ "${QSC_PS_NOW:-0}" -ge "${QSC_PS_WAIT_NEXT_RETRY:-0}" ] 2>/dev/null || return 1
	fi
	return 0
}

# 未插电该睡多久，结果写入 QSC_PS_IDLE_EFF。
# 有守护时可以睡得更久：插电由 uevent 立刻叫醒，等待间隔不再决定响应速度，
# 而它恰好是待机功耗的主要旋钮。没有守护则必须沿用 loop_interval_idle_sec，
# 否则插上充电器要等满一个间隔才被发现。
qsc_ps_idle_secs() {
	QSC_PS_IDLE_EFF="${QSC_PS_IDLE:-30}"
	QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
	# 正在看管理器：主服务短睡自己刷简介（有 XP 时无 worker）
	if type qsc_desc_viewing_active >/dev/null 2>&1 &&
		qsc_desc_viewing_active; then
		if type qsc_ps_screen_is_off >/dev/null 2>&1 &&
			qsc_ps_screen_is_off; then
			type qsc_desc_viewing_clear >/dev/null 2>&1 &&
				qsc_desc_viewing_clear
		else
			if type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
				QSC_PS_IDLE_EFF=45
			else
				QSC_PS_IDLE_EFF=60
			fi
			QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
			return 0
		fi
	fi
	qsc_ps_native_ready || {
		type qsc_ps_policy_refresh >/dev/null 2>&1 && qsc_ps_policy_refresh
		[ -n "${QSC_PS_IDLE_EFF:-}" ] && QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
		return 0
	}
	[ "${QSC_PS_IDLE_NATIVE:-0}" -gt "$QSC_PS_IDLE_EFF" ] 2>/dev/null \
		&& QSC_PS_IDLE_EFF="$QSC_PS_IDLE_NATIVE"
	# 档位 / 息屏 / 夜间 DeepPark 可再放大（仅未插电）
	type qsc_ps_policy_refresh >/dev/null 2>&1 && qsc_ps_policy_refresh
	QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
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

qsc_ps_native_exec() {
	local secs="$1" limit marker rc pid killer
	shift
	case "$secs" in ""|*[!0-9]*) secs=30 ;; esac
	limit=$((secs + 5))
	marker="$DATADIR/.qsc_exec_done.$$"
	rm -f "$marker" 2>/dev/null
	# 子进程跑 qscd（可阻塞数十～数百秒）。禁止用 sleep 1 轮询：那会把
	# 「事件等待省电」打回成约 1Hz 的 shell 唤醒，待机比纯 sleep 还费电。
	# 主路径 wait 子进程；旁路 sleep+kill 仅作挂死兜底，平时不醒来。
	(
		"$@"
		rc="$?"
		printf '%s\n' "$rc" >"$marker" 2>/dev/null
		exit "$rc"
	) &
	pid=$!
	(
		sleep "$limit"
		if [ ! -f "$marker" ]; then
			kill -9 "$pid" 2>/dev/null
		fi
	) &
	killer=$!
	wait "$pid" 2>/dev/null
	rc="$?"
	kill "$killer" 2>/dev/null
	wait "$killer" 2>/dev/null || true
	if [ -f "$marker" ]; then
		rc="$(cat "$marker" 2>/dev/null | tr -d ' \r\n')"
		rm -f "$marker" 2>/dev/null
		case "$rc" in ""|*[!0-9]*) rc=124 ;; esac
		# region agent log
		type qsc_runtime_trace >/dev/null 2>&1 &&
			qsc_runtime_trace "H3" "native_launcher" "wait:$rc"
		# endregion
		return "$rc"
	fi
	rm -f "$marker" 2>/dev/null
	# region agent log
	type qsc_runtime_trace >/dev/null 2>&1 &&
		qsc_runtime_trace "H3" "native_launcher" "wait:124"
	# endregion
	return 124
}

# 交给守护等待。支持 watch 时把阈值一起交下去：充电中「离阈值还远」的
# uevent 由它自己吞掉，不再每轮叫醒 shell；插拔与跨阈值仍立即返回。
# 未插电 / 停充维持：只关心插拔（哨兵 --temp-stop 999），不把电流温度噪声当事件。
qsc_ps_native_wait() {
	local secs="$1" floor="$2" rc error_file wake_args=""
	error_file="$DATADIR/qscd_wait_error.$$"
	# Rust：简介开着时把 viewer 边沿并进 qscd poll，省掉 shell inotify 竞速
	if type qsc_native_has >/dev/null 2>&1 && qsc_native_has wake-file &&
		type qsc_description_enabled >/dev/null 2>&1 &&
		qsc_description_enabled &&
		[ "${QSC_PS_PROFILE:-balanced}" != "aggressive" ] &&
		[ -d /data/system ]; then
		if type qsc_xp_ensure_bus >/dev/null 2>&1; then
			qsc_xp_ensure_bus /data/system/qsc_xp_viewer || true
		fi
		wake_args="--wake-file /data/system/qsc_xp_viewer"
	fi
	qsc_dbg "qscd wait 进入 secs=$secs floor=$floor watch=$([ -x "$BINDIR/qscd" ] && qsc_ps_watch_supported && echo 1 || echo 0) switch=$([ -f "$DATADIR/power_switch" ] && echo 1 || echo 0)"
	if qsc_ps_watch_supported; then
		QSC_PS_NATIVE_MODE=watch
		# region agent log
		type qsc_runtime_trace >/dev/null 2>&1 &&
			qsc_runtime_trace "H3" "native_wait_enter" "$QSC_PS_NATIVE_MODE:$secs:$floor"
		# endregion
		if [ ! -f "$DATADIR/power_switch" ] && qsc_ps_plugged; then
			# shellcheck disable=SC2086
			qsc_ps_native_exec "$secs" "$BINDIR/qscd" watch --max "$secs" --floor "$floor" \
				--stop "${QSC_PS_STOP:-101}" --near "${QSC_PS_NEAR:-3}" \
				--temp-stop "${QSC_PS_TEMP_STOP:-999}" $wake_args > /dev/null 2>"$error_file"
			rc="$?"
		else
			# shellcheck disable=SC2086
			qsc_ps_native_exec "$secs" "$BINDIR/qscd" watch --max "$secs" --floor "$floor" \
				--temp-stop 999 $wake_args > /dev/null 2>"$error_file"
			rc="$?"
		fi
	else
		# C 版只有 wait-event（无法过滤）。未插电若照用，效果同上：电池噪声
		# 整夜唤醒。改为直接走外层 sleep，插电仍用 wait-event 保响应。
		if ! qsc_ps_plugged && [ ! -f "$DATADIR/power_switch" ]; then
			QSC_PS_NATIVE_MODE=sleep-idle
			QSC_PS_NATIVE_ERROR=idle_no_watch
			# region agent log
			type qsc_runtime_trace >/dev/null 2>&1 &&
				qsc_runtime_trace "H3" "native_wait_enter" "$QSC_PS_NATIVE_MODE:$secs:$floor"
			# endregion
			sleep "$secs"
			rc=0
			rm -f "$error_file" 2>/dev/null
			# region agent log
			type qsc_runtime_trace >/dev/null 2>&1 &&
				qsc_runtime_trace "H3" "native_wait_exit" "$QSC_PS_NATIVE_MODE:$rc"
			# endregion
			return 0
		fi
		QSC_PS_NATIVE_MODE=wait-event
		# region agent log
		type qsc_runtime_trace >/dev/null 2>&1 &&
			qsc_runtime_trace "H3" "native_wait_enter" "$QSC_PS_NATIVE_MODE:$secs:$floor"
		# endregion
		qsc_ps_native_exec "$secs" "$BINDIR/qscd" wait-event "$secs" "$floor" \
			> /dev/null 2>"$error_file"
		rc="$?"
	fi
	# region agent log
	type qsc_runtime_trace >/dev/null 2>&1 &&
		qsc_runtime_trace "H3" "native_wait_exit" "$QSC_PS_NATIVE_MODE:$rc"
	# endregion
	if [ "$rc" -eq 124 ]; then
		QSC_PS_NATIVE_ERROR=timeout
	else
		qsc_ps_native_parse_stderr "$error_file"
	fi
	[ -n "$QSC_PS_NATIVE_ERROR" ] || QSC_PS_NATIVE_ERROR=wait_failed
	qsc_dbg "qscd wait 结束 mode=${QSC_PS_NATIVE_MODE:-?} rc=$rc err=${QSC_PS_NATIVE_ERROR:-?} secs=$secs floor=$floor"
	rm -f "$error_file" 2>/dev/null
	# region agent log
	type qsc_runtime_trace >/dev/null 2>&1 &&
		qsc_runtime_trace "H3" "native_wait_reason" "$QSC_PS_NATIVE_MODE:$rc:$QSC_PS_NATIVE_ERROR:${QSC_PS_NATIVE_WAKE:-}"
	# endregion
	if [ "$rc" -eq 0 ]; then
		qsc_ps_log_native_wake
		return 0
	fi
	return "$rc"
}

qsc_ps_mark_native_failure() {
	local rc="$1" now="${QSC_PS_NOW:-0}" reason="${QSC_PS_NATIVE_ERROR:-wait_failed}" wall
	wall="$(date +%F_%T 2>/dev/null)"
	case "$now" in ""|*[!0-9]*) now=0 ;; esac
	case "$reason" in ""|*[!a-zA-Z0-9_-]*) reason=wait_failed ;;
	esac
	printf 'reason=%s\nmode=%s\nrc=%s\nat=%s\ntime=%s\n' \
		"$reason" "${QSC_PS_NATIVE_MODE:-unknown}" "$rc" "$now" "$wall" \
		>"$DATADIR/qscd_unusable.tmp" 2>/dev/null &&
		mv -f "$DATADIR/qscd_unusable.tmp" "$DATADIR/qscd_unusable" 2>/dev/null
	# 武装 XP 边沿唤醒（system_server 写 /data/system/qsc_xp_wake）；软关闭则跳过
	if [ -f /data/system/qsc_xp_off ]; then
		type qsc_xp_file_log >/dev/null 2>&1 &&
			qsc_xp_file_log WARN "magisk: xp soft-off, skip arm (qscd unusable reason=$reason)"
		return 0
	fi
	touch /data/system/qsc_xp_arm 2>/dev/null || true
	type qsc_xp_file_log >/dev/null 2>&1 &&
		qsc_xp_file_log WARN "ok magisk: xp armed (qscd unusable reason=$reason)"
}

# XP 唤醒文件是否在近几秒内更新（root 可读 /data/system）
qsc_ps_xp_wake_fresh() {
	local f=/data/system/qsc_xp_wake mt now
	[ -f "$f" ] || return 1
	mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
	now="$(date +%s 2>/dev/null || echo 0)"
	case "$mt:$now" in *[!0-9:]*) return 1 ;; esac
	[ "$mt" -gt 0 ] 2>/dev/null && [ "$((now - mt))" -le 20 ] 2>/dev/null
}

# XP 管理器边沿待消费（非空队列）→ 可打断主服务长睡
qsc_ps_xp_viewer_pending() {
	type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
		qsc_manager_viewer_xp_edge_pending
}

# 可选辅助边沿（亮灭屏/Doze/广播）亦可武装打断；与 wake 同窗口
qsc_ps_xp_assist_fresh() {
	local now mt age f
	[ -f /data/system/qsc_xp_off ] && return 1
	now="$(date +%s 2>/dev/null || echo 0)"
	case "$now" in ""|*[!0-9]*) return 1 ;; esac
	for f in /data/system/qsc_xp_screen /data/system/qsc_xp_doze /data/system/qsc_xp_bcast; do
		[ -f "$f" ] || continue
		case "$f" in
			*/qsc_xp_screen) [ -f /data/system/qsc_xp_want_screen ] || continue ;;
			*/qsc_xp_doze) [ -f /data/system/qsc_xp_want_doze ] || continue ;;
			*/qsc_xp_bcast) [ -f /data/system/qsc_xp_want_bcast ] || continue ;;
		esac
		mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
		case "$mt" in ""|*[!0-9]*) continue ;; esac
		age=$((now - mt))
		if [ "$mt" -gt 0 ] 2>/dev/null && [ "$age" -ge 0 ] 2>/dev/null &&
			[ "$age" -le 20 ] 2>/dev/null; then
			return 0
		fi
	done
	return 1
}

# 简介开时：qscd 与 viewer 边沿竞速。
# 返回：0=viewer 打断或 native 成功；1=无法竞速（调用方走可打断短片，勿整段盲等）；其它=native 失败码
qsc_ps_wait_race_viewer() {
	local secs="$1" floor="${2:-3}" vf=/data/system/qsc_xp_viewer
	local qpid ipid rc=0
	case "$secs" in ""|*[!0-9]*) secs=30 ;; esac
	[ "$secs" -lt 1 ] 2>/dev/null && secs=1
	# CI / 非 Android：无 /data/system 则不竞速
	[ -d /data/system ] || return 1
	qsc_ps_xp_viewer_pending && return 0
	if ! command -v inotifywait >/dev/null 2>&1; then
		return 1
	fi
	# 占位，否则 consume 后文件消失，inotify 挂不上；0666 供 XP append
	if type qsc_xp_ensure_bus >/dev/null 2>&1; then
		qsc_xp_ensure_bus "$vf" || return 1
	elif [ ! -e "$vf" ]; then
		: >"$vf" 2>/dev/null || return 1
		chmod 0666 "$vf" 2>/dev/null || true
	else
		chmod 0666 "$vf" 2>/dev/null || true
	fi
	(
		qsc_ps_native_wait "$secs" "$floor"
	) &
	qpid=$!
	(
		inotifywait -qq -t "$secs" \
			-e modify,attrib,close_write,create,move \
			"$vf" 2>/dev/null || true
		# 边沿到：立刻打断 native，勿再 sleep 1 轮询
		kill "$qpid" 2>/dev/null || true
	) &
	ipid=$!
	wait "$qpid" 2>/dev/null
	rc=$?
	kill "$ipid" 2>/dev/null || true
	wait "$ipid" 2>/dev/null || true
	# inotify 先到会杀 native（非 0）；以 pending 为准
	if qsc_ps_xp_viewer_pending; then
		return 0
	fi
	# native 正常睡满
	[ "$rc" -eq 0 ] 2>/dev/null && return 0
	# 被 inotify 杀掉但无 pending：当作竞速失败交还调用方，勿伪装成成功
	return "$rc"
}

# qscd 不可用时的睡眠：武装 XP / 简介边沿均可短片打断
qsc_ps_fallback_sleep() {
	local secs="${1:-3}" left chunk=3
	case "$secs" in ""|*[!0-9]*) secs=3 ;; esac
	if qsc_ps_xp_viewer_pending; then
		return 0
	fi
	if [ -f /data/system/qsc_xp_off ]; then
		sleep "$secs"
		return 0
	fi
	# 简介边沿：仅 pending/观看才短片；勿因「开了动态简介」整夜高频醒
	_desc_wake=0
	if type qsc_ps_xp_viewer_pending >/dev/null 2>&1 &&
		qsc_ps_xp_viewer_pending; then
		_desc_wake=1
	elif type qsc_desc_viewing_active >/dev/null 2>&1 &&
		qsc_desc_viewing_active; then
		_desc_wake=1
	fi
	if [ "$_desc_wake" != "1" ] && [ ! -f /data/system/qsc_xp_arm ]; then
		sleep "$secs"
		return 0
	fi
	if [ -f /data/system/qsc_xp_no_wake ] && [ "$_desc_wake" != "1" ]; then
		sleep "$secs"
		return 0
	fi
	if qsc_ps_xp_wake_fresh || qsc_ps_xp_assist_fresh || qsc_ps_xp_viewer_pending; then
		rm -f /data/system/qsc_xp_wake 2>/dev/null || true
		return 0
	fi
	left=$secs
	while [ "$left" -gt 0 ] 2>/dev/null; do
		chunk=15
		[ "$_desc_wake" = "1" ] && chunk=5
		[ "$left" -lt "$chunk" ] 2>/dev/null && chunk=$left
		sleep "$chunk"
		left=$((left - chunk))
		if qsc_ps_xp_wake_fresh || qsc_ps_xp_assist_fresh ||
			qsc_ps_xp_viewer_pending; then
			rm -f /data/system/qsc_xp_wake 2>/dev/null || true
			return 0
		fi
	done
}

# 息屏驻停中：过夜应纯 qscd，勿挂 viewer 竞速/短片睡
qsc_ps_wait_parked_screen_off() {
	type qsc_ps_screen_is_off >/dev/null 2>&1 || return 1
	qsc_ps_screen_is_off || return 1
	case "${QSC_PS_MODE:-}" in
		deep|screen_off) return 0 ;;
	esac
	[ "${QSC_PS_PARK_ACTIVE:-0}" = "1" ] && return 0
	[ "${QSC_PS_DESC_FORCE_STATIC:-0}" = "1" ] && return 0
	[ "${QSC_PS_DEEP:-0}" = "1" ] && return 0
	return 1
}

# 是否与 viewer 竞速：仅 pending/观看/非驻停息屏时；驻停息屏纯事件睡。
# qscd 已支持 --wake-file 时不必再挂 shell inotify。
qsc_ps_wait_should_race_viewer() {
	type qsc_description_enabled >/dev/null 2>&1 || return 1
	qsc_description_enabled || return 1
	[ "${QSC_PS_PROFILE:-balanced}" = "aggressive" ] && return 1
	if type qsc_native_has >/dev/null 2>&1 && qsc_native_has wake-file; then
		return 1
	fi
	if type qsc_ps_xp_viewer_pending >/dev/null 2>&1 &&
		qsc_ps_xp_viewer_pending; then
		return 0
	fi
	if type qsc_desc_viewing_active >/dev/null 2>&1 &&
		qsc_desc_viewing_active; then
		return 0
	fi
	qsc_ps_wait_parked_screen_off && return 1
	return 0
}

qsc_ps_wait() {
	local secs="${1:-30}" floor fallback_secs
	local rc backoff now
	floor="${QSC_PS_WAIT_FLOOR:-3}"
	[ "$secs" -lt "$floor" ] 2>/dev/null && floor="$secs"
	fallback_secs="${QSC_PS_WAIT_FALLBACK:-${QSC_PS_LOOP:-3}}"
	case "$fallback_secs" in ""|*[!0-9]*) fallback_secs=3 ;;
	esac
	# 省电诊断：累加计划睡眠秒（实际可能被 uevent 提前叫醒）
	case "$secs" in
		""|*[!0-9]*) ;;
		*)
			QSC_PS_SLEEP_SEC_SUM=$((${QSC_PS_SLEEP_SEC_SUM:-0} + secs))
			QSC_PS_SLEEP_COUNT=$((${QSC_PS_SLEEP_COUNT:-0} + 1))
			;;
	esac
	if qsc_ps_native_ready; then
		_race=0
		_race_rc=1
		if qsc_ps_wait_should_race_viewer; then
			_race=1
		fi
		if [ "$_race" = "1" ]; then
			qsc_ps_wait_race_viewer "$secs" "$floor"
			_race_rc="$?"
		fi
		if [ "$_race" = "1" ] && [ "$_race_rc" -eq 0 ] 2>/dev/null; then
			if [ "$QSC_PS_WAIT_FAILURES" -gt 0 ] 2>/dev/null; then
				qsc_log info "事件等待器已恢复（${QSC_PS_NATIVE_MODE:-wait}）"
			fi
			QSC_PS_WAIT_HELPER_OK=1
			QSC_PS_WAIT_FAILURES=0
			QSC_PS_WAIT_NEXT_RETRY=0
			rm -f "$DATADIR/qscd_unusable" /data/system/qsc_xp_arm 2>/dev/null
			qsc_log_once_clear qscd
			return 0
		fi
		# 无法竞速（无 inotify 等）：一律改走 native，勿盲 sleep 丢掉插拔与 enter
		if [ "$_race" = "1" ] && [ "$_race_rc" -eq 1 ] 2>/dev/null; then
			qsc_ps_native_wait "$secs" "$floor"
			rc="$?"
		elif [ "$_race" = "1" ] && [ "$_race_rc" -ne 1 ] 2>/dev/null; then
			rc="$_race_rc"
		else
			qsc_ps_native_wait "$secs" "$floor"
			rc="$?"
		fi
		if [ "$rc" -eq 0 ]; then
			if [ "$QSC_PS_WAIT_FAILURES" -gt 0 ] 2>/dev/null; then
				qsc_log info "事件等待器已恢复（${QSC_PS_NATIVE_MODE:-wait}）"
			fi
			QSC_PS_WAIT_HELPER_OK=1
			QSC_PS_WAIT_FAILURES=0
			QSC_PS_WAIT_NEXT_RETRY=0
			rm -f "$DATADIR/qscd_unusable" /data/system/qsc_xp_arm 2>/dev/null
			qsc_log_once_clear qscd
			return 0
		fi
		QSC_PS_WAIT_HELPER_OK=0
		QSC_PS_WAIT_FAILURES=$((QSC_PS_WAIT_FAILURES + 1))
		backoff=30
		[ "$QSC_PS_WAIT_FAILURES" -gt 1 ] && backoff=60
		[ "$QSC_PS_WAIT_FAILURES" -gt 2 ] && backoff=300
		[ "$QSC_PS_WAIT_FAILURES" -gt 3 ] && backoff=900
		now="${QSC_PS_NOW:-0}"
		case "$now" in ""|*[!0-9]*) now=0 ;; esac
		QSC_PS_WAIT_NEXT_RETRY=$((now + backoff))
		# region agent log
		type qsc_runtime_trace >/dev/null 2>&1 &&
			qsc_runtime_trace "H9" "native_failure_enter" "$rc:$backoff"
		# endregion
		qsc_ps_mark_native_failure "$rc"
		# region agent log
		type qsc_runtime_trace >/dev/null 2>&1 &&
			qsc_runtime_trace "H9" "failure_marker_exit" "$?"
		# endregion
		qsc_log_once qscd warn "事件等待器不可用（${QSC_PS_NATIVE_MODE:-?} rc=${rc} reason=${QSC_PS_NATIVE_ERROR}），已退回定时轮询"
		# region agent log
		type qsc_runtime_trace >/dev/null 2>&1 &&
			qsc_runtime_trace "H9" "failure_log_exit" "$?"
		# endregion
		qsc_ps_record_wake "守护不可用，已退回定时轮询"
		# region agent log
		type qsc_runtime_trace >/dev/null 2>&1 &&
			qsc_runtime_trace "H9" "failure_wake_exit" "$?"
		# endregion
		# 未插电失败回退：禁止掉进 loop=3 短睡；至少按 idle 地板
		if type qsc_ps_plugged >/dev/null 2>&1 && ! qsc_ps_plugged; then
			_floor="${QSC_PS_IDLE:-90}"
			case "$_floor" in ""|*[!0-9]*) _floor=90 ;; esac
			[ "$_floor" -lt 90 ] 2>/dev/null && _floor=90
			[ "$fallback_secs" -lt "$_floor" ] 2>/dev/null && fallback_secs="$_floor"
			# 首次失败也拉长，避免抖成 1Hz 级
			[ "$QSC_PS_WAIT_FAILURES" -le 1 ] 2>/dev/null &&
				[ "$fallback_secs" -lt 120 ] 2>/dev/null &&
				fallback_secs=120
		fi
	fi
	# region agent log
	type qsc_runtime_trace >/dev/null 2>&1 &&
		qsc_runtime_trace "H9" "fallback_sleep_enter" "$fallback_secs"
	# endregion
	qsc_ps_fallback_sleep "$fallback_secs"
	# region agent log
	type qsc_runtime_trace >/dev/null 2>&1 &&
		qsc_runtime_trace "H9" "fallback_sleep_exit" "$?"
	# endregion
}

# 本轮结束后应睡多久
# 参数: 电量 停充电量 是否插电(1/0) [温度 停充温度]
qsc_ps_next_sleep() {
	local level="$1" stop="$2" plugged="$3" temp="$4" temp_stop="$5" _pl _m
	if [ "${QSC_PS_ENABLE:-1}" != "1" ]; then
		QSC_PS_WAIT_FALLBACK="${QSC_PS_LOOP:-3}"
		echo "${QSC_PS_LOOP:-3}"
		return 0
	fi
	# 维持停充：按场景拉长（MCA 除外）；持锁与否由 wakelock 策略单独决定
	if [ -f "$DATADIR/power_switch" ] && [ ! -f "$MODULE_OFF_FLAG" ]; then
		if type qsc_ps_maintain_secs >/dev/null 2>&1; then
			type qsc_ps_now >/dev/null 2>&1 && qsc_ps_now
			qsc_ps_maintain_secs
			_m="${QSC_PS_MAINTAIN_EFF:-${QSC_PS_MAINTAIN:-30}}"
		else
			_m="${QSC_PS_MAINTAIN:-30}"
			if [ -f "$DATADIR/wakelock_held" ]; then
				if type qsc_device_is_mca >/dev/null 2>&1 && qsc_device_is_mca; then
					:
				else
					_m=300
					[ "${QSC_PS_MAINTAIN:-0}" -gt 60 ] 2>/dev/null && _m="$QSC_PS_MAINTAIN"
				fi
			fi
		fi
		QSC_PS_WAIT_FALLBACK="$_m"
		echo "$_m"
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
		QSC_PS_WAIT_FALLBACK="${QSC_PS_LOOP:-3}"
		echo "${QSC_PS_LOOP:-3}"
		return 0
	fi

	# 温度上升比电量快，接近温控阈值时同样收紧间隔
	case "$temp$temp_stop" in
		""|*[!0-9]*) ;;
		*)
			if [ "$((temp_stop - temp))" -le 3 ] 2>/dev/null; then
				QSC_PS_WAIT_FALLBACK="${QSC_PS_LOOP:-3}"
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
	QSC_PS_WAIT_FALLBACK="${QSC_PS_PLUGGED:-10}"
	echo "$_pl"
}
