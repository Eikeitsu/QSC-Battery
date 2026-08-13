#!/system/bin/sh
# 音量键读取（安装 customize 与 Action 共用）
# 返回：0=音量上，1=音量下，2=超时或无法读取
# 可选参数：超时秒数（默认 20）
#
# - 只认 KEY_* DOWN（认 UP 会把松手当成新选择）
# - 先短时 drain 残留按键，避免提示未看清就选中
# - 用剩余整段时间阻塞等下一条，减少轮询漏键
# - 等待过程不刷屏；仅结果输出（上/下/超时）

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

qsc_volume_match_up() {
	grep -qE 'KEY_VOLUMEUP[[:space:]]+DOWN|[[:space:]]0073[[:space:]]+00000001' "$1" 2>/dev/null
}

qsc_volume_match_down() {
	grep -qE 'KEY_VOLUMEDOWN[[:space:]]+DOWN|[[:space:]]0072[[:space:]]+00000001' "$1" 2>/dev/null
}

qsc_volume_read_one() {
	out="$1"
	ge="$2"
	max_sec="$3"
	pid=""
	w=0

	case "$max_sec" in
		""|*[!0-9]*) max_sec=1 ;;
	esac
	[ "$max_sec" -ge 1 ] || max_sec=1

	rm -f "$out"
	: >"$out"

	if command -v timeout >/dev/null 2>&1; then
		timeout "$max_sec" "$ge" -lqc 1 >"$out" 2>/dev/null || true
		return 0
	fi

	"$ge" -lqc 1 >"$out" 2>/dev/null &
	pid=$!
	while [ "$w" -lt "$max_sec" ]; do
		kill -0 "$pid" 2>/dev/null || break
		[ -s "$out" ] && break
		sleep 1
		w=$((w + 1))
	done
	kill "$pid" 2>/dev/null || true
	wait "$pid" 2>/dev/null || true
	return 0
}

# 约 1s 内吞掉残留按键
qsc_volume_drain() {
	ge="$1"
	event_file="$2"
	until_ts=0
	now_ts=0

	until_ts=$(date +%s 2>/dev/null) || until_ts=0
	if [ "$until_ts" -gt 0 ]; then
		until_ts=$((until_ts + 1))
		while true; do
			now_ts=$(date +%s 2>/dev/null) || break
			[ "$now_ts" -ge "$until_ts" ] && break
			qsc_volume_read_one "$event_file" "$ge" 1
			[ -s "$event_file" ] || break
		done
	else
		qsc_volume_read_one "$event_file" "$ge" 1
	fi
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

	case "$timeout_sec" in
		""|*[!0-9]*) timeout_sec=20 ;;
	esac
	[ "$timeout_sec" -ge 3 ] || timeout_sec=3

	event_file="${TMPDIR:-/data/local/tmp}/qsc-key-events.$$"
	ge="$(qsc_volume_getevent_bin)" || return 2
	[ -n "$ge" ] || return 2

	qsc_volume_drain "$ge" "$event_file"

	start_ts=$(date +%s 2>/dev/null) || start_ts=0
	elapsed=0

	while [ "$elapsed" -lt "$timeout_sec" ]; do
		remaining=$((timeout_sec - elapsed))
		[ "$remaining" -lt 1 ] && remaining=1
		qsc_volume_read_one "$event_file" "$ge" "$remaining"
		if [ -s "$event_file" ]; then
			if qsc_volume_match_up "$event_file"; then
				rm -f "$event_file"
				echo "  → 音量上"
				return 0
			fi
			if qsc_volume_match_down "$event_file"; then
				rm -f "$event_file"
				echo "  → 音量下"
				return 1
			fi
		fi

		if [ "$start_ts" -gt 0 ]; then
			now_ts=$(date +%s 2>/dev/null) || now_ts=0
			if [ "$now_ts" -gt 0 ]; then
				elapsed=$((now_ts - start_ts))
			else
				elapsed=$((elapsed + 1))
			fi
		else
			elapsed=$((elapsed + 1))
		fi
	done

	rm -f "$event_file"
	echo "  → 等待超时"
	return 2
}
