#!/system/bin/sh
# 音量键读取（安装脚本 / Action 菜单共用）
# 返回：0=音量上，1=音量下，2=超时或无法读取
# 可选参数：超时秒数（默认 20）
# 注意：每次调用独立计时；开始前会丢弃上一轮按键残留，避免误判为立刻选择/跳过

qsc_volume_choice() {
	local timeout_sec="${1:-20}"
	local event_file event_pid
	local start_ts now_ts elapsed

	event_file="${TMPDIR:-/data/local/tmp}/qsc-key-events.$$"
	rm -f "$event_file"

	if ! command -v getevent >/dev/null 2>&1; then
		return 2
	fi

	getevent -ql >"$event_file" 2>/dev/null &
	event_pid=$!

	# 丢弃上一轮按键的 UP/重复/缓冲，再开始本轮计时
	sleep 1
	: >"$event_file"

	start_ts=$(date +%s 2>/dev/null) || start_ts=0
	elapsed=0
	while [ "$elapsed" -lt "$timeout_sec" ]; do
		if grep -q 'KEY_VOLUMEUP.*DOWN' "$event_file" 2>/dev/null; then
			kill "$event_pid" 2>/dev/null
			wait "$event_pid" 2>/dev/null
			rm -f "$event_file"
			return 0
		fi
		if grep -q 'KEY_VOLUMEDOWN.*DOWN' "$event_file" 2>/dev/null; then
			kill "$event_pid" 2>/dev/null
			wait "$event_pid" 2>/dev/null
			rm -f "$event_file"
			return 1
		fi
		sleep 1
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

	kill "$event_pid" 2>/dev/null
	wait "$event_pid" 2>/dev/null
	rm -f "$event_file"
	return 2
}
