#!/system/bin/sh
# 通用小工具：超时读节点、温度归一化、调试步进

qsc_debug_step() {
	echo "$(date +%F_%T) step$1" >> "$DATADIR/debug.log"
}

# 避免个别 sysfs 读阻塞拖死主循环
qsc_safe_cat() {
	cat "$1" > "$DATADIR/.safe_tmp" 2>/dev/null &
	local _pid=$!
	local _i
	for _i in 1 2; do
		if [ ! -d "/proc/$_pid" ]; then break; fi
		sleep 1
	done
	kill $_pid 2>/dev/null
	cat "$DATADIR/.safe_tmp" 2>/dev/null
}

# dumpsys/sysfs 温度统一到摄氏度整数
qsc_normalize_temperature() {
	local raw digits normalized
	raw="$(echo "$1" | tr -d ' \r\n')"
	case "$raw" in ""|"-"|*[!0-9-]*) return 1 ;; esac
	digits="${raw#-}"
	case "$digits" in ""|*[!0-9]*) return 1 ;; esac
	if [ "$digits" -ge 10000 ]; then
		normalized=$((raw / 1000))
	elif [ "$digits" -ge 1000 ]; then
		normalized=$((raw / 100))
	elif [ "$digits" -ge 100 ]; then
		normalized=$((raw / 10))
	else
		normalized="$raw"
	fi
	[ "$normalized" -ge -20 -a "$normalized" -le 100 ] || return 1
	echo "$normalized"
}

# 兼容旧名
_debug_step() { qsc_debug_step "$@"; }
_safe_cat() { qsc_safe_cat "$@"; }
_normalize_temperature() { qsc_normalize_temperature "$@"; }
