#!/system/bin/sh
# 音量键读取（安装脚本 / Action 菜单共用）
# 返回：0=音量上，1=音量下，2=超时或无法读取
# 可选参数：超时秒数（默认 20）
#
# 注意：
# - 只认 KEY_* DOWN（认 UP 会把「松开」当成新一次选择，表现为莫名跳过/结束）
# - 用短窗轮询 + 心跳输出：Action 界面若长时间无 stdout，部分管理器会直接杀掉脚本

qsc_volume_getevent_bin() {
	if [ -x /system/bin/getevent ]; then
		echo /system/bin/getevent
		return 0
	fi
	if [ -x /system/xbin/getevent ]; then
		echo /system/xbin/getevent
		return 0
	fi
	command -v getevent 2>/dev/null
}

# 仅 DOWN，避免残留 UP / 松手事件误触发
qsc_volume_match_up() {
	grep -qE 'KEY_VOLUMEUP[[:space:]]+DOWN|[[:space:]]0073[[:space:]]+00000001' "$1" 2>/dev/null
}

qsc_volume_match_down() {
	grep -qE 'KEY_VOLUMEDOWN[[:space:]]+DOWN|[[:space:]]0072[[:space:]]+00000001' "$1" 2>/dev/null
}

# 单次最多等 slice_sec 秒，取到任意一条 getevent 即返回（可能是非音量）
qsc_volume_read_one() {
	local out="$1"
	local ge="$2"
	local slice_sec="$3"
	local pid w

	case "$slice_sec" in
		""|*[!0-9]*) slice_sec=2 ;;
	esac
	[ "$slice_sec" -ge 1 ] || slice_sec=1
	[ "$slice_sec" -gt 3 ] && slice_sec=3

	rm -f "$out"
	: >"$out"

	if command -v timeout >/dev/null 2>&1; then
		# 短超时，避免 Action 长时间无输出被管理器杀掉
		timeout "$slice_sec" "$ge" -lqc 1 >"$out" 2>/dev/null || true
		return 0
	fi

	"$ge" -lqc 1 >"$out" 2>/dev/null &
	pid=$!
	w=0
	while [ "$w" -lt "$slice_sec" ]; do
		kill -0 "$pid" 2>/dev/null || break
		[ -s "$out" ] && break
		sleep 1
		w=$((w + 1))
	done
	kill "$pid" 2>/dev/null || true
	wait "$pid" 2>/dev/null || true
	return 0
}

# 排空缓冲：约 1.2s 内持续吞事件，降低「提示未看清就已选中」
qsc_volume_drain() {
	local ge="$1"
	local event_file="$2"
	local n=0

	while [ "$n" -lt 8 ]; do
		qsc_volume_read_one "$event_file" "$ge" 1
		[ -s "$event_file" ] || break
		n=$((n + 1))
	done
	rm -f "$event_file"
}

qsc_volume_choice() {
	local timeout_sec="${1:-20}"
	local event_file ge
	local start_ts now_ts elapsed remaining slice
	local last_hb=-99

	case "$timeout_sec" in
		""|*[!0-9]*) timeout_sec=20 ;;
	esac
	[ "$timeout_sec" -ge 3 ] || timeout_sec=3

	event_file="${TMPDIR:-/data/local/tmp}/qsc-key-events.$$"
	ge="$(qsc_volume_getevent_bin)" || return 2
	[ -n "$ge" ] || return 2

	# BusyBox ash 无 RETURN trap；用常见信号 + 退出前手动清理
	trap 'rm -f "'"$event_file"'" 2>/dev/null' HUP INT TERM PIPE

	qsc_volume_drain "$ge" "$event_file"

	start_ts=$(date +%s 2>/dev/null) || start_ts=0
	elapsed=0
	echo "  …等待音量键（${timeout_sec}s 内有效；仅按下时生效）"

	while [ "$elapsed" -lt "$timeout_sec" ]; do
		remaining=$((timeout_sec - elapsed))
		[ "$remaining" -lt 1 ] && remaining=1
		# 每片最多 2s，中间可打心跳，避免管理器因无输出杀进程
		slice=2
		[ "$remaining" -lt "$slice" ] && slice="$remaining"

		# 约每 3 秒一行心跳（stdout 保活）
		if [ $((elapsed - last_hb)) -ge 3 ]; then
			echo "  …仍在等待（已 ${elapsed}/${timeout_sec}s）"
			last_hb=$elapsed
		fi

		qsc_volume_read_one "$event_file" "$ge" "$slice"
		if [ -s "$event_file" ]; then
			if qsc_volume_match_up "$event_file"; then
				rm -f "$event_file"
				trap - HUP INT TERM PIPE
				echo "  → 音量上"
				return 0
			fi
			if qsc_volume_match_down "$event_file"; then
				rm -f "$event_file"
				trap - HUP INT TERM PIPE
				echo "  → 音量下"
				return 1
			fi
			# 其它输入事件：忽略，继续等
		fi

		if [ "$start_ts" -gt 0 ]; then
			now_ts=$(date +%s 2>/dev/null) || now_ts=0
			if [ "$now_ts" -gt 0 ]; then
				elapsed=$((now_ts - start_ts))
			else
				elapsed=$((elapsed + slice))
			fi
		else
			elapsed=$((elapsed + slice))
		fi
	done

	rm -f "$event_file"
	trap - HUP INT TERM PIPE
	echo "  → 等待超时"
	return 2
}
