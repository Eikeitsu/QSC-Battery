#!/system/bin/sh
# 音量键读取（安装脚本 / Action 菜单共用）
# 返回：0=音量上，1=音量下，2=超时或无法读取
# 可选参数：超时秒数（默认 20）
#
# 要点：
# - 不用「每秒开一次 getevent -c 1」的短窗轮询（容易漏掉 DOWN，连按才偶发命中）
# - 每次用「本轮剩余秒数」阻塞等待下一条事件；非音量事件立刻再等
# - DOWN / UP 都算有效，避免只收到抬起时被当成没按

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
	# 标签 DOWN/UP，或原始码 KEY_VOLUMEUP(0x73) value 1/0
	grep -qE 'KEY_VOLUMEUP[[:space:]]+(DOWN|UP)|[[:space:]]0073[[:space:]]+0000000[01]' "$1" 2>/dev/null
}

qsc_volume_match_down() {
	# KEY_VOLUMEDOWN(0x72)
	grep -qE 'KEY_VOLUMEDOWN[[:space:]]+(DOWN|UP)|[[:space:]]0072[[:space:]]+0000000[01]' "$1" 2>/dev/null
}

# 阻塞至多 max_sec 秒，抓取 1 条输入事件
qsc_volume_read_one() {
	local out="$1"
	local ge="$2"
	local max_sec="$3"
	local pid w

	[ "$max_sec" -ge 1 ] || max_sec=1
	rm -f "$out"
	touch "$out" 2>/dev/null

	if command -v timeout >/dev/null 2>&1; then
		timeout "$max_sec" "$ge" -lqc 1 >"$out" 2>/dev/null
		return 0
	fi

	"$ge" -lqc 1 >"$out" 2>/dev/null &
	pid=$!
	w=0
	while [ "$w" -lt "$max_sec" ]; do
		kill -0 "$pid" 2>/dev/null || break
		[ -s "$out" ] && break
		sleep 1
		w=$((w + 1))
	done
	kill "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null
	return 0
}

# 最多约 1 秒清空队列残留，避免上一轮抬起键被当成本轮输入
qsc_volume_drain() {
	local ge="$1"
	local event_file="$2"
	local until_ts now_ts

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
	local timeout_sec="${1:-20}"
	local event_file ge
	local start_ts now_ts elapsed remaining

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
				return 0
			fi
			if qsc_volume_match_down "$event_file"; then
				rm -f "$event_file"
				return 1
			fi
			# 触摸等杂讯：立刻继续等下一条，不空等 1 秒
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
	return 2
}
