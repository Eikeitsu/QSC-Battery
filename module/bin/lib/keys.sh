#!/system/bin/sh
# 音量键读取（安装脚本 / Action 菜单共用）
# 返回：0=音量上，1=音量下，2=超时或无法读取
# 可选参数：超时秒数（默认 20）
#
# 注意：
# - 只认 KEY_* DOWN（认 UP 会把「松开」当成新一次选择）
# - 安装界面不会因短暂无输出杀脚本；Action（SukiSU/KSU 等）约 1–2s 无 stdout 会杀
# - 因此仅 Action 需要保活输出；安装保持安静，等待日志不是功能必需

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

qsc_volume_in_action() {
	case "${0##*/}" in
		action.sh) return 0 ;;
	esac
	[ "${QSC_VOLUME_KEEPALIVE:-0}" = "1" ]
}

qsc_volume_match_up() {
	grep -qE 'KEY_VOLUMEUP[[:space:]]+DOWN|[[:space:]]0073[[:space:]]+00000001' "$1" 2>/dev/null
}

qsc_volume_match_down() {
	grep -qE 'KEY_VOLUMEDOWN[[:space:]]+DOWN|[[:space:]]0072[[:space:]]+00000001' "$1" 2>/dev/null
}

# Action 保活：尽量短，避免刷屏；安装路径不调用
qsc_volume_keepalive() {
	qsc_volume_in_action || return 0
	# 管道全缓冲时 stderr 更易被 Action 界面立刻吃到
	printf '%s\n' "$1"
	printf '%s\n' "$1" >&2
}

qsc_volume_read_one() {
	local out="$1"
	local ge="$2"
	local slice_sec="$3"
	local pid w

	case "$slice_sec" in
		""|*[!0-9]*) slice_sec=1 ;;
	esac
	[ "$slice_sec" -ge 1 ] || slice_sec=1
	# Action 下单次阻塞不超过 1s；安装可稍长以降低漏键
	if qsc_volume_in_action; then
		[ "$slice_sec" -gt 1 ] && slice_sec=1
	else
		[ "$slice_sec" -gt 3 ] && slice_sec=3
	fi

	rm -f "$out"
	: >"$out"

	if command -v timeout >/dev/null 2>&1; then
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

qsc_volume_drain() {
	local ge="$1"
	local event_file="$2"
	local n=0
	local max=6
	local slice=1

	qsc_volume_in_action || max=8
	while [ "$n" -lt "$max" ]; do
		# 安装安静清键；Action 只打极简点，避免长中文刷屏
		qsc_volume_keepalive "."
		qsc_volume_read_one "$event_file" "$ge" "$slice"
		[ -s "$event_file" ] || break
		n=$((n + 1))
	done
	rm -f "$event_file"
}

qsc_volume_choice() {
	local timeout_sec="${1:-20}"
	local event_file ge
	local start_ts now_ts elapsed remaining slice

	case "$timeout_sec" in
		""|*[!0-9]*) timeout_sec=20 ;;
	esac
	[ "$timeout_sec" -ge 3 ] || timeout_sec=3

	event_file="${TMPDIR:-/data/local/tmp}/qsc-key-events.$$"
	ge="$(qsc_volume_getevent_bin)" || return 2
	[ -n "$ge" ] || return 2

	trap 'rm -f "'"$event_file"'" 2>/dev/null' HUP INT TERM
	trap '' PIPE

	qsc_volume_drain "$ge" "$event_file"

	start_ts=$(date +%s 2>/dev/null) || start_ts=0
	elapsed=0
	# 对人可见的提示只打一次；后续保活用 "."（仅 Action）
	echo "  …等待音量键（${timeout_sec}s 内有效；仅按下时生效）"

	while [ "$elapsed" -lt "$timeout_sec" ]; do
		remaining=$((timeout_sec - elapsed))
		[ "$remaining" -lt 1 ] && remaining=1
		if qsc_volume_in_action; then
			slice=1
			qsc_volume_keepalive "."
		else
			slice=2
			[ "$remaining" -lt "$slice" ] && slice="$remaining"
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
