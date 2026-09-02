#!/system/bin/sh
# 充放电历史：每日健康趋势追加 + 事件日志暴露给主循环
# （原 charge_history.csv 保持不变；新增 health_history.csv）

QSC_HEALTH_FILE="${QSC_HEALTH_FILE:-$DATADIR/health_history.csv}"

qsc_health_sample_daily() {
	local today stamp soh cycles have
	# 当日已经采样过就跳过
	today="$(date '+%Y-%m-%d' 2>/dev/null)" || return 0
	stamp="$(date '+%s' 2>/dev/null)" || return 0
	[ -f "$QSC_HEALTH_FILE" ] || {
		mkdir -p "$DATADIR" 2>/dev/null
		echo "ts,soh,cycle_count" >"$QSC_HEALTH_FILE"
	}
	have=""
	[ -f "$DATADIR/health_last_day" ] && have="$(cat "$DATADIR/health_last_day" 2>/dev/null | tr -d ' \r\n')"
	[ "$have" = "$today" ] && return 0

	soh="$(qsc_cat_node "$PSDIR/battery/health_type" 2>/dev/null)"
	# 优先 SOH 数值节点（部分机型百分比 0-100）
	for p in "$PSDIR/battery/battery_health" "$PSDIR/battery/soh" \
		"$PSDIR/battery/SOH" "$PSDIR/battery/cycle_total"; do
		[ -r "$p" ] || continue
		case "$p" in
			*cycle_total|*cycle*)
				[ -z "$cycles" ] && cycles="$(qsc_cat_node "$p" 2>/dev/null)"
				;;
			*)
				[ -z "$soh" ] && soh="$(qsc_cat_node "$p" 2>/dev/null)"
				;;
		esac
	done
	# 归一：soh 百分比；cycles 纯数字
	soh="$(printf '%s' "$soh" | tr -d ', %')"
	cycles="$(printf '%s' "$cycles" | tr -d ', ')"
	case "$soh" in ""|*[!0-9.]*) soh="--" ;; esac
	case "$cycles" in ""|*[!0-9]*) cycles="--" ;; esac

	echo "${stamp},${soh},${cycles}" >>"$QSC_HEALTH_FILE" 2>/dev/null || return 1
	echo "$today" >"$DATADIR/health_last_day" 2>/dev/null
	return 0
}
