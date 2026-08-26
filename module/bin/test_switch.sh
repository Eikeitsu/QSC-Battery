#!/system/bin/sh
# 停充开关实测（保守）：逐条测可逆有效节点，写入 device.profile
# 用法（adb，须插电）：sh /data/adb/modules/QSC_Battery/bin/test_switch.sh
# 不在 Action 音量菜单内；测完必恢复充电。

. "${0%/*}/common.sh"

OUT="${DATADIR}/switch_test.log"
mkdir -p "$DATADIR" 2>/dev/null
: >"$OUT"
echo "running ts=$(date +%s)" >"$DATADIR/switch_test_status"

qsc_abs_ua() {
	local c
	c="$(qsc_safe_cat /sys/class/power_supply/battery/current_now 2>/dev/null)"
	c="$(echo "$c" | sed 's/-//g' | tr -d ' \r\n')"
	echo "${c:-0}"
}

qsc_batt_status() {
	qsc_safe_cat /sys/class/power_supply/battery/status 2>/dev/null
}

qsc_is_plugged() {
	local s o
	s="$(qsc_batt_status)"
	case "$s" in
		Charging|Full) return 0 ;;
	esac
	for o in /sys/class/power_supply/usb/online \
		/sys/class/power_supply/qc_usb/online \
		/sys/class/power_supply/dc/online \
		/sys/class/power_supply/wireless/online; do
		[ -f "$o" ] && [ "$(qsc_safe_cat "$o")" = "1" ] && return 0
	done
	return 1
}

# 跳过电流墙类「伪开关」，避免测试时乱改限流
qsc_switch_entry_safe() {
	local entry="$1"
	case "$entry" in
		*constant_charge_current*|*input_current_max*|*charge_current*|*fast_charge*|*current_max*)
			return 1
			;;
		*charge_type*|*charge_control_end*|*charger_limit,*)
			return 1
			;;
	esac
	return 0
}

qsc_parse_entry() {
	ENTRY_PATH="$(echo "$1" | sed -n 's/,start=.*//g;$p')"
	ENTRY_START="$(echo "$1" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
	ENTRY_STOP="$(echo "$1" | sed -n 's/.*,stop=//g;s/_/ /g;$p')"
}

# 返回 0=判定为已停充倾向
qsc_looks_stopped() {
	local st cur
	st="$(qsc_batt_status)"
	cur="$(qsc_abs_ua)"
	case "$st" in
		Discharging|"Not charging") return 0 ;;
	esac
	# 插着电但电流很小，视为接近停充/idle（阈值保守）
	[ "$cur" -lt 80000 ] 2>/dev/null && return 0
	return 1
}

qsc_looks_charging() {
	local st cur
	st="$(qsc_batt_status)"
	cur="$(qsc_abs_ua)"
	case "$st" in
		Charging|Full)
			[ "$cur" -gt 50000 ] 2>/dev/null && return 0
			# Full 且电流很小也算恢复成功（已充满）
			[ "$st" = "Full" ] && return 0
			;;
	esac
	[ "$cur" -gt 100000 ] 2>/dev/null && return 0
	return 1
}

echo "========================================"
echo " 停充开关实测"
echo "========================================"
echo " 日志: $OUT"

if ! qsc_is_plugged; then
	echo "[错误] 请先插入充电器再测试"
	echo "not_plugged" >"$DATADIR/switch_test_result"
	echo "error not_plugged ts=$(date +%s)" >"$DATADIR/switch_test_status"
	qsc_log error "停充开关实测失败：未插充电器"
	exit 1
fi

if [ ! -f "$LIST_SWITCH" ] && [ -f "$BINDIR/list_switch.sh" ]; then
	chmod 0755 "$BINDIR/list_switch.sh"
	"$BINDIR/list_switch.sh" >/dev/null 2>&1
fi

qsc_build_switch_list

# 去重路径，保留首个完整 entry
CAND_FILE="$DATADIR/.switch_cand.$$"
: >"$CAND_FILE"
SEEN_FILE="$DATADIR/.switch_seen.$$"
: >"$SEEN_FILE"
for i in $switch_list; do
	qsc_switch_entry_safe "$i" || continue
	qsc_parse_entry "$i"
	[ -n "$ENTRY_PATH" ] && [ -f "$ENTRY_PATH" ] || continue
	[ -n "$ENTRY_START" ] && [ -n "$ENTRY_STOP" ] || continue
	if grep -qxF "$ENTRY_PATH" "$SEEN_FILE" 2>/dev/null; then
		continue
	fi
	echo "$ENTRY_PATH" >>"$SEEN_FILE"
	echo "$i" >>"$CAND_FILE"
done
rm -f "$SEEN_FILE"

cand_n="$(wc -l <"$CAND_FILE" 2>/dev/null | tr -d ' ')"
# Action 快速模式：QSC_TEST_MAX=N 只测前 N 条
if [ -n "${QSC_TEST_MAX:-}" ]; then
	case "$QSC_TEST_MAX" in
		*[!0-9]*|"") ;;
		*)
			if [ "$QSC_TEST_MAX" -gt 0 ] 2>/dev/null && [ "${cand_n:-0}" -gt "$QSC_TEST_MAX" ] 2>/dev/null; then
				head -n "$QSC_TEST_MAX" "$CAND_FILE" >"${CAND_FILE}.max" 2>/dev/null && mv -f "${CAND_FILE}.max" "$CAND_FILE"
				cand_n="$QSC_TEST_MAX"
				echo " 快速模式: 仅测前 ${cand_n} 条（完整测试勿设 QSC_TEST_MAX）"
			fi
			;;
	esac
fi
echo " 候选开关: ${cand_n:-0} 条（已排除电流墙类节点）"
echo "候选数=$cand_n 时间=$(date +%F_%T) max=${QSC_TEST_MAX:-all}" >>"$OUT"

BEST_ENTRY=""
BEST_PATH=""
ok_n=0
fail_n=0
idx=0

while IFS= read -r entry; do
	[ -n "$entry" ] || continue
	idx=$((idx + 1))
	qsc_parse_entry "$entry"
	echo ""
	echo "[$idx/$cand_n] $ENTRY_PATH"
	echo "  start=$ENTRY_START stop=$ENTRY_STOP" | tee -a "$OUT"

	before_st="$(qsc_batt_status)"
	before_c="$(qsc_abs_ua)"
	echo "  测前: status=$before_st current=${before_c}uA" | tee -a "$OUT"

	# 基线需像在充电，否则跳过（避免误判）
	if ! qsc_looks_charging; then
		echo "  跳过: 测前未处于明显充电状态" | tee -a "$OUT"
		fail_n=$((fail_n + 1))
		continue
	fi

	qsc_write_node "$ENTRY_PATH" "$ENTRY_STOP"
	sleep 2
	after_st="$(qsc_batt_status)"
	after_c="$(qsc_abs_ua)"
	echo "  停充后: status=$after_st current=${after_c}uA" | tee -a "$OUT"

	stopped=0
	if qsc_looks_stopped; then
		stopped=1
	elif [ "$after_c" -lt "$((before_c / 3))" ] 2>/dev/null && [ "$after_c" -lt 200000 ]; then
		stopped=1
	fi

	# 无论成败，先恢复
	qsc_write_node "$ENTRY_PATH" "$ENTRY_START"
	sleep 2
	rest_st="$(qsc_batt_status)"
	rest_c="$(qsc_abs_ua)"
	echo "  恢复后: status=$rest_st current=${rest_c}uA" | tee -a "$OUT"

	restored=0
	if qsc_looks_charging; then
		restored=1
	elif [ "$rest_c" -gt 80000 ] 2>/dev/null; then
		restored=1
	fi

	# 再保险：写一遍 start
	qsc_write_node "$ENTRY_PATH" "$ENTRY_START"

	if [ "$stopped" = "1" ] && [ "$restored" = "1" ]; then
		echo "  结果: 有效且可逆 ✓" | tee -a "$OUT"
		ok_n=$((ok_n + 1))
		if [ -z "$BEST_ENTRY" ]; then
			BEST_ENTRY="$entry"
			BEST_PATH="$ENTRY_PATH"
		fi
	else
		echo "  结果: 无效或不可逆 ✗ (stopped=$stopped restored=$restored)" | tee -a "$OUT"
		fail_n=$((fail_n + 1))
	fi
done <"$CAND_FILE"
rm -f "$CAND_FILE"

# 最终确保恢复：通用 start 一轮
qsc_power_start >/dev/null 2>&1 || true

echo ""
echo "========================================"
if [ -n "$BEST_ENTRY" ]; then
	qsc_parse_entry "$BEST_ENTRY"
	qsc_set_preferred_switch "$ENTRY_PATH" "$ENTRY_START" "$ENTRY_STOP"
	echo " 已选定首选开关:"
	echo "  $ENTRY_PATH"
	echo "  start=$ENTRY_START stop=$ENTRY_STOP"
	echo " 已写入 device.profile (preferred_switch)"
	echo "ok path=$ENTRY_PATH" >"$DATADIR/switch_test_result"
	echo "done ok path=$ENTRY_PATH ts=$(date +%s)" >"$DATADIR/switch_test_status"
	qsc_log info "首选开关 $ENTRY_PATH start=$ENTRY_START stop=$ENTRY_STOP"
else
	echo " 未找到可逆有效开关"
	echo " 将继续使用多节点兜底；可查看 $OUT"
	echo "none" >"$DATADIR/switch_test_result"
	echo "done none ts=$(date +%s)" >"$DATADIR/switch_test_status"
	qsc_log warn "停充开关实测未找到可逆有效节点，继续多节点兜底"
	qsc_clear_preferred_switch
fi
echo " 有效=$ok_n 无效/跳过=$fail_n"
echo "========================================"
echo " 测试结束（已尝试恢复充电）"
rm -f "$DATADIR/switch_test_pid" 2>/dev/null
