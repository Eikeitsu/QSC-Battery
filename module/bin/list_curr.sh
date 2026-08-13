#!/system/bin/sh
# 电流控制节点探测（仅在充电时扫描）
# 主路径：power_supply/*/constant_charge_current_max（排除 usb 等输入口）
# 补充：电池侧其它上限节点、restrict*_cur*（仍排除 usb）
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

qsc_list_curr_is_charging() {
	local st
	st="$(cat /sys/class/power_supply/battery/status 2>/dev/null | tr -d ' \r\n')"
	case "$st" in
		Charging|Full|Quick\ Charge*|Fast\ Charging*) return 0 ;;
	esac
	st="$(cat /sys/class/power_supply/usb/online 2>/dev/null | tr -d ' \r\n')"
	[ "$st" = "1" ] && return 0
	st="$(cat /sys/class/power_supply/battery/online 2>/dev/null | tr -d ' \r\n')"
	[ "$st" = "1" ] && return 0
	return 1
}

# 输入口 / 非电池通路：不参与电流写入探测
qsc_list_curr_is_input_psy() {
	case "$1" in
		*/power_supply/usb/*|*/power_supply/qc_usb/*|*/power_supply/pc_port/*| \
		*/power_supply/dc/*|*/power_supply/wireless/*|*/power_supply/usb_pd/*)
			return 0
			;;
	esac
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
	qsc_list_curr_is_input_psy "$node" && return 0
	return 1
}

# 主列表：各 power_supply 下 constant_charge_current_max（除输入口）
qsc_list_curr_collect_primary() {
	local f
	for f in /sys/class/power_supply/*/constant_charge_current_max; do
		[ -f "$f" ] || continue
		qsc_list_curr_is_input_psy "$f" && continue
		echo "$f"
	done
	for f in \
		/sys/class/power_supply/main/constant_charge_current_max \
		/sys/class/power_supply/battery/constant_charge_current_max \
		; do
		[ -f "$f" ] && echo "$f"
	done
}

# 补充列表：电池/main 其它上限 + restrict（排除 usb）
qsc_list_curr_collect_aux() {
	local f tmp="$DATADIR/.ch_curr_aux_build"
	: >"$tmp"
	# 常见电池侧电流节点（排除 usb）
	for f in \
		/sys/class/power_supply/main/constant_charge_current \
		/sys/class/power_supply/battery/constant_charge_current \
		/sys/class/power_supply/battery/fast_charge_current \
		/sys/class/power_supply/battery/fast_charge_current_max \
		/sys/class/power_supply/battery/current_max \
		/sys/class/power_supply/main/current_max \
		/sys/class/qcom-battery/restrict_cur \
		/sys/class/qcom-battery/restrict_current \
		/sys/class/qcom-battery/batt_tune_chg_limit_cur \
		/sys/class/qcom-battery/batt_tune_chg_limit_current \
		/sys/class/qcom-battery/batt_tune_fast_chg_cur \
		/sys/class/qcom-battery/batt_tune_fcc_cur \
		/sys/class/qcom-battery/siop_input_current \
		/sys/class/qcom-battery/siop_level \
		; do
		[ -f "$f" ] && echo "$f" >>"$tmp"
	done
	find /sys/class/qcom-battery/ /sys/class/power_supply/battery/ /sys/class/power_supply/main/ \
		-maxdepth 2 -type f \( -name '*restrict*_cur*' -o -name 'batt_tune_*cur*' \) 2>/dev/null >>"$tmp"
	find /sys/ -name '*restrict*_cur*' 2>/dev/null \
		| egrep -i -v 'usb|qc_usb|wireless|pc_port' >>"$tmp" 2>/dev/null
	sort -u "$tmp"
	rm -f "$tmp"
}

qsc_list_curr_emit_line() {
	local file="$1" defaultValue scale
	[ -f "$file" ] || return 1
	qsc_list_curr_denied "$file" && return 1
	case "$file" in
		*parallel*) return 1 ;;
		*/bq*/current_max|*bq[0-9]*/current_max) return 1 ;;
	esac
	chmod a+r "$file" 2>/dev/null || return 1
	defaultValue="$(cat "$file" 2>/dev/null | tr -d ' \r\n')" || return 1
	case "$defaultValue" in
		""|-*|[01]|*[!0-9]*) return 1 ;;
	esac
	[ "$defaultValue" -lt 1 ] 2>/dev/null && return 1

	# constant_charge_current_max 按微安写入（目标 mA×1000）
	case "$file" in
		*/constant_charge_current_max)
			scale=1
			# 若读回像 mA（<10000），仍按 µA 目标写，scale 保持 1，default 记原值
			;;
		*)
			if [ "$defaultValue" -lt 10000 ]; then
				scale=1000
			else
				scale=1
			fi
			;;
	esac
	echo "${file}::${scale}::${defaultValue}"
}

if [ "$FORCE" != "1" ] && ! qsc_list_curr_is_charging; then
	if [ -s "$CH_CURR_CTRL" ]; then
		echo "[QSC] list_curr.sh: 未在充电，保留已有探测结果 ($(wc -l <"$CH_CURR_CTRL" | tr -d ' ') 条)" >&2
	else
		echo "[QSC] list_curr.sh: 未在充电且无历史列表，跳过探测（插电后重试）" >&2
	fi
	exit 0
fi

tmp_out="$DATADIR/.ch_curr_ctrl_tmp"
: >"$tmp_out"
prim="$DATADIR/.ch_curr_prim"
aux="$DATADIR/.ch_curr_aux"

qsc_list_curr_collect_primary | sort -u >"$prim"
qsc_list_curr_collect_aux | sort -u >"$aux"

while IFS= read -r file || [ -n "$file" ]; do
	file="$(printf '%s' "$file" | tr -d ' \r\n')"
	[ -n "$file" ] || continue
	qsc_list_curr_emit_line "$file" >>"$tmp_out"
done <"$prim"

# 主路径为空时才把补充节点并入；主路径有结果时也合并补充（排在后面由写入侧排序）
while IFS= read -r file || [ -n "$file" ]; do
	file="$(printf '%s' "$file" | tr -d ' \r\n')"
	[ -n "$file" ] || continue
	# 已在主列表则跳过
	grep -qxF "$file" "$prim" 2>/dev/null && continue
	qsc_list_curr_emit_line "$file" >>"$tmp_out"
done <"$aux"

rm -f "$prim" "$aux"

if [ -s "$tmp_out" ]; then
	sort -u "$tmp_out" -o "$CH_CURR_CTRL"
	n="$(wc -l <"$CH_CURR_CTRL" | tr -d ' ')"
	echo "[QSC] list_curr.sh: 探测到 $n 个电流节点 → $CH_CURR_CTRL" >&2
	if [ -n "${LOG_FILE:-}" ]; then
		echo "$(date +%F_%T) 电流控制：节点探测完成，$n 个节点" >>"$LOG_FILE"
	fi
else
	if [ ! -s "$CH_CURR_CTRL" ]; then
		: >"$CH_CURR_CTRL"
	fi
	echo "[QSC] list_curr.sh: 本轮未找到可用电流节点" >&2
fi
rm -f "$tmp_out"
exit 0
