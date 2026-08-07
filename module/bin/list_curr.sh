#!/system/bin/sh
# 电流控制节点探测（仅在充电时扫描，识别 mA/µA）
# 输出：$DATADIR/ch_curr_ctrl_files
# 行格式：绝对路径::scale::default
#   scale=1    → 节点单位为 µA
#   scale=1000 → 节点单位为 mA（写入时目标µA/1000）
#
# 用法：list_curr.sh [force]
#   force=1 时跳过「是否在充」检查（调试用）

. "${0%/*}/common.sh"

CH_CURR_CTRL="${CH_CURR_CTRL_FILES:-$DATADIR/ch_curr_ctrl_files}"
FORCE="${1:-0}"
mkdir -p "$DATADIR" 2>/dev/null

# 是否在充电（非充电时读数常为 0，不可信）
qsc_list_curr_is_charging() {
	local st
	st="$(cat /sys/class/power_supply/battery/status 2>/dev/null | tr -d ' \r\n')"
	case "$st" in
		Charging|Full|Quick\ Charge*|Fast\ Charging*) return 0 ;;
	esac
	# 部分机型用 usb/online
	st="$(cat /sys/class/power_supply/usb/online 2>/dev/null | tr -d ' \r\n')"
	[ "$st" = "1" ] && return 0
	st="$(cat /sys/class/power_supply/battery/online 2>/dev/null | tr -d ' \r\n')"
	[ "$st" = "1" ] && return 0
	return 1
}

qsc_list_curr_denied() {
	local node="$1" base
	base="${node##*/}"
	case "$base" in
		charge_control_limit|thermal_input_current|charge_current|current_now|voltage_now|status|capacity|temp|type|uevent)
			return 0
			;;
	esac
	return 1
}

# 候选路径收集（用 find 扫描常见电流上限节点）
# 输出到 stdout（调用方重定向到文件）
qsc_list_curr_collect_candidates() {
	local tmp="$DATADIR/.ch_curr_cand_build"
	: >"$tmp"

	# power_supply / qcom-battery 常规节点
	find /sys/class/power_supply/ /sys/class/qcom-battery/ \
		-maxdepth 2 -type f \( \
		-name 'constant_charge_current' -o \
		-name 'constant_charge_current_max' -o \
		-name 'fast_charge_current' -o \
		-name 'fast_charge_current_max' -o \
		-name 'current_max' -o \
		-name 'input_current_max' -o \
		-name 'input_current_limit' -o \
		-name '*restrict*_cur*' -o \
		-name 'batt_tune_*_charge_current' \
		\) 2>/dev/null >>"$tmp"

	# 全树 restrict（排除 usb）
	find /sys/ -name '*restrict*_cur*' 2>/dev/null \
		| egrep -i -v 'usb' >>"$tmp" 2>/dev/null

	# 常见绝对路径兜底（含 main 通路）
	for f in \
		/sys/class/power_supply/main/constant_charge_current_max \
		/sys/class/power_supply/battery/constant_charge_current \
		/sys/class/power_supply/battery/constant_charge_current_max \
		/sys/class/power_supply/battery/fast_charge_current \
		/sys/class/power_supply/battery/current_max \
		/sys/class/power_supply/battery/input_current_max \
		/sys/class/power_supply/usb/current_max \
		/sys/class/power_supply/usb/input_current_max \
		/sys/class/qcom-battery/restrict_cur \
		/sys/class/qcom-battery/restrict_current \
		; do
		[ -f "$f" ] && echo "$f" >>"$tmp"
	done

	# 枚举所有 power_supply 下的 constant_charge_current_max
	for f in /sys/class/power_supply/*/constant_charge_current_max; do
		[ -f "$f" ] && echo "$f" >>"$tmp"
	done

	sort -u "$tmp"
	rm -f "$tmp"
}

if [ "$FORCE" != "1" ] && ! qsc_list_curr_is_charging; then
	# 未在充：保留旧列表，不覆盖为空
	if [ -s "$CH_CURR_CTRL" ]; then
		echo "[QSC] list_curr.sh: 未在充电，保留已有探测结果 ($(wc -l <"$CH_CURR_CTRL" | tr -d ' ') 条)" >&2
	else
		echo "[QSC] list_curr.sh: 未在充电且无历史列表，跳过探测（插电后重试）" >&2
	fi
	exit 0
fi

tmp_out="$DATADIR/.ch_curr_ctrl_tmp"
cand="$DATADIR/.ch_curr_cand"
: >"$tmp_out"
qsc_list_curr_collect_candidates >"$cand"

while IFS= read -r file || [ -n "$file" ]; do
	file="$(printf '%s' "$file" | tr -d ' \r\n')"
	[ -n "$file" ] || continue
	[ -f "$file" ] || continue
	qsc_list_curr_denied "$file" && continue

	# 排除 parallel、bq*/current_max
	case "$file" in
		*parallel*) continue ;;
		*/bq*/current_max|*bq[0-9]*/current_max) continue ;;
	esac

	chmod a+r "$file" 2>/dev/null || continue
	defaultValue="$(cat "$file" 2>/dev/null | tr -d ' \r\n')" || continue

	# 过滤：空、负、0/1、非纯数字
	case "$defaultValue" in
		""|-*|[01]|*[!0-9]*) continue ;;
	esac
	[ "$defaultValue" -lt 1 ] 2>/dev/null && continue

	if [ "$defaultValue" -lt 10000 ]; then
		# milliamps
		scale=1000
	else
		# microamps
		scale=1
	fi

	echo "${file}::${scale}::${defaultValue}" >>"$tmp_out"
done <"$cand"
rm -f "$cand"

if [ -s "$tmp_out" ]; then
	sort -u "$tmp_out" -o "$CH_CURR_CTRL"
	n="$(wc -l <"$CH_CURR_CTRL" | tr -d ' ')"
	echo "[QSC] list_curr.sh: 探测到 $n 个电流节点 → $CH_CURR_CTRL" >&2
	if [ -n "${LOG_FILE:-}" ]; then
		echo "$(date +%F_%T) 电流控制：节点探测完成，$n 个节点" >>"$LOG_FILE"
	fi
else
	# 探测为空：不抹掉旧列表
	if [ ! -s "$CH_CURR_CTRL" ]; then
		: >"$CH_CURR_CTRL"
	fi
	echo "[QSC] list_curr.sh: 本轮未找到可用电流节点" >&2
fi
rm -f "$tmp_out"
exit 0
