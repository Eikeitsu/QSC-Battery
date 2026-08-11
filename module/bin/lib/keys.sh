#!/system/bin/sh
# 音量键读取（安装脚本 / Action 菜单共用）
# 返回：0=音量上，1=音量下，2=超时或无法读取
# 可选参数：超时秒数（默认 20）
#
# Action（SukiSU/KSU）约 1–2s 无 stdout 会杀脚本；安装无此限制。
# 第一次等待正常、第二次被杀：常见于 getevent/timeout 残留占住输入设备，
# 第二次阻塞时又没有并行心跳。故 Action 下：
#   1) 不用 timeout 包 getevent（改后台启动 + 到期强杀）
#   2) 整段等待期间后台并行输出保活

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

qsc_volume_hb_pid=""

qsc_volume_hb_stop() {
	if [ -n "$qsc_volume_hb_pid" ]; then
		kill "$qsc_volume_hb_pid" 2>/dev/null || true
		wait "$qsc_volume_hb_pid" 2>/dev/null || true
		qsc_volume_hb_pid=""
	fi
}

# 并行保活：不依赖 getevent 是否返回
qsc_volume_hb_start() {
	qsc_volume_in_action || return 0
	qsc_volume_hb_stop
	(
		n=0
		while [ "$n" -lt 120 ]; do
			# 有实质内容，避免部分管理器忽略单字符/空行
			printf '.\n'
			printf '.\n' >&2
			sleep 1
			n=$((n + 1))
		done
	) &
	qsc_volume_hb_pid=$!
}

qsc_volume_ge_pid=""

qsc_volume_kill_getevent() {
	if [ -n "$qsc_volume_ge_pid" ]; then
		kill "$qsc_volume_ge_pid" 2>/dev/null || true
		kill -9 "$qsc_volume_ge_pid" 2>/dev/null || true
		wait "$qsc_volume_ge_pid" 2>/dev/null || true
		qsc_volume_ge_pid=""
	fi
}

qsc_volume_read_one() {
	out="$1"
	ge="$2"
	slice_sec="$3"
	w=0

	case "$slice_sec" in
		""|*[!0-9]*) slice_sec=1 ;;
	esac
	[ "$slice_sec" -ge 1 ] || slice_sec=1
	if qsc_volume_in_action; then
		[ "$slice_sec" -gt 1 ] && slice_sec=1
	else
		[ "$slice_sec" -gt 3 ] && slice_sec=3
	fi

	rm -f "$out"
	: >"$out"

	qsc_volume_kill_getevent
	# 一律后台 + 到期强杀；不用 timeout（部分机型对 getevent 杀不干净，第二次必挂）
	"$ge" -lqc 1 >"$out" 2>/dev/null &
	qsc_volume_ge_pid=$!
	w=0
	while [ "$w" -lt "$slice_sec" ]; do
		kill -0 "$qsc_volume_ge_pid" 2>/dev/null || break
		[ -s "$out" ] && break
		sleep 1
		w=$((w + 1))
	done
	qsc_volume_kill_getevent
	return 0
}

qsc_volume_drain() {
	ge="$1"
	event_file="$2"
	n=0
	max=4

	qsc_volume_in_action && max=3
	while [ "$n" -lt "$max" ]; do
		qsc_volume_read_one "$event_file" "$ge" 1
		[ -s "$event_file" ] || break
		n=$((n + 1))
	done
	rm -f "$event_file"
}

qsc_volume_choice() {
	timeout_sec="${1:-20}"
	event_file=""
	ge=""
	start_ts=0
	now_ts=0
	elapsed=0
	remaining=0
	slice=1
	rc=2

	case "$timeout_sec" in
		""|*[!0-9]*) timeout_sec=20 ;;
	esac
	[ "$timeout_sec" -ge 3 ] || timeout_sec=3

	event_file="${TMPDIR:-/data/local/tmp}/qsc-key-events.$$"
	ge="$(qsc_volume_getevent_bin)" || return 2
	[ -n "$ge" ] || return 2

	qsc_volume_hb_start
	trap 'qsc_volume_hb_stop; qsc_volume_kill_getevent; rm -f "'"$event_file"'" 2>/dev/null' HUP INT TERM
	trap '' PIPE

	qsc_volume_drain "$ge" "$event_file"

	start_ts=$(date +%s 2>/dev/null) || start_ts=0
	elapsed=0
	echo "  …等待音量键（${timeout_sec}s 内有效；仅按下时生效）"

	while [ "$elapsed" -lt "$timeout_sec" ]; do
		remaining=$((timeout_sec - elapsed))
		[ "$remaining" -lt 1 ] && remaining=1
		if qsc_volume_in_action; then
			slice=1
		else
			slice=2
			[ "$remaining" -lt "$slice" ] && slice="$remaining"
		fi

		qsc_volume_read_one "$event_file" "$ge" "$slice"
		if [ -s "$event_file" ]; then
			if qsc_volume_match_up "$event_file"; then
				rc=0
				echo "  → 音量上"
				break
			fi
			if qsc_volume_match_down "$event_file"; then
				rc=1
				echo "  → 音量下"
				break
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

	if [ "$elapsed" -ge "$timeout_sec" ] && [ "$rc" -eq 2 ]; then
		echo "  → 等待超时"
		rc=2
	fi

	rm -f "$event_file"
	qsc_volume_kill_getevent
	qsc_volume_hb_stop
	trap - HUP INT TERM PIPE
	return "$rc"
}
