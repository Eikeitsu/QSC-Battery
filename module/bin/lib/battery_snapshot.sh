#!/system/bin/sh
# 统一电池快照：Shell 决策、模块简介和 WebUI 共用同一套读取优先级。
#
# 输出变量（调用 qsc_battery_snapshot_read 后可直接使用）：
# QSC_BATTERY_LEVEL / QSC_BATTERY_TEMP / QSC_BATTERY_STATUS
# QSC_BATTERY_POWERED / QSC_BATTERY_SOURCE / QSC_BATTERY_READ_AT

qsc_battery_snapshot_read() {
	QSC_BATTERY_LEVEL=""
	QSC_BATTERY_TEMP=""
	QSC_BATTERY_STATUS=""
	QSC_BATTERY_POWERED=""
	QSC_BATTERY_SOURCE=""
	QSC_BATTERY_READ_AT=""
	_QSC_SNAP_CAP=""
	_QSC_SNAP_STATUS=""
	_QSC_SNAP_TEMP=""

	# battery 是主节点，bms/soc/temp 仅在主节点缺失或不可解析时兜底。
	for _QSC_SNAP_CAP_PATH in "$PSDIR/battery/capacity" \
		"$PSDIR/bms/capacity" "$PSDIR/battery/soc"; do
		qsc_read_node "$_QSC_SNAP_CAP_PATH" || continue
		case "$QSC_NODE_VAL" in
			""|*[!0-9]*) continue ;;
		esac
		_QSC_SNAP_CAP="$QSC_NODE_VAL"
		case "$_QSC_SNAP_CAP_PATH" in
			"$PSDIR/battery/capacity") QSC_BATTERY_SOURCE="battery" ;;
			"$PSDIR/bms/capacity") QSC_BATTERY_SOURCE="bms" ;;
			*) QSC_BATTERY_SOURCE="soc" ;;
		esac
		break
	done

	for _QSC_SNAP_STATUS_PATH in "$PSDIR/battery/status" "$PSDIR/bms/status"; do
		qsc_read_node "$_QSC_SNAP_STATUS_PATH" || continue
		[ -n "$QSC_NODE_VAL" ] || continue
		_QSC_SNAP_STATUS="$QSC_NODE_VAL"
		break
	done

	for _QSC_SNAP_TEMP_PATH in "$PSDIR/battery/temp" \
		"$PSDIR/bms/temp" "$PSDIR/battery/batt_temp"; do
		qsc_read_node "$_QSC_SNAP_TEMP_PATH" || continue
		_QSC_SNAP_TEMP="$(qsc_normalize_temperature "$QSC_NODE_VAL")"
		[ -n "$_QSC_SNAP_TEMP" ] || continue
		break
	done

	case "$_QSC_SNAP_STATUS" in
		Charging)
			QSC_BATTERY_STATUS=2
			QSC_BATTERY_POWERED="powered: true"
			;;
		Full)
			QSC_BATTERY_STATUS=5
			QSC_BATTERY_POWERED="powered: true"
			;;
		Discharging)
			QSC_BATTERY_STATUS=3
			;;
		"Not charging")
			QSC_BATTERY_STATUS=4
			;;
	esac

	# status=Not charging 在 MCA/K90U 上仍可能代表插线；统一交给供电
	# 信号判定，qsc_ps_plugged 内置时再复用它的完整兼容逻辑。
	if [ -z "$QSC_BATTERY_POWERED" ] &&
		type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
		QSC_BATTERY_POWERED="powered: true"
	fi

	if [ -n "$_QSC_SNAP_CAP" ] && [ -n "$QSC_BATTERY_STATUS" ] &&
		[ -n "$_QSC_SNAP_TEMP" ]; then
		QSC_BATTERY_LEVEL="$_QSC_SNAP_CAP"
		QSC_BATTERY_TEMP="$_QSC_SNAP_TEMP"
		QSC_BATTERY_READ_AT="$(date +%s 2>/dev/null)"
		[ -n "$QSC_BATTERY_SOURCE" ] || QSC_BATTERY_SOURCE="sysfs"
		return 0
	fi

	# sysfs 不完整时才调用 binder，避免待机每轮唤醒 system_server。
	_QSC_SNAP_DUMPSYS=""
	if command -v dumpsys >/dev/null 2>&1; then
		_QSC_SNAP_DUMPSYS="$(dumpsys battery 2>/dev/null)"
	fi
	if [ -n "$_QSC_SNAP_DUMPSYS" ]; then
		QSC_BATTERY_LEVEL="$(qsc_dumpsys_level "$_QSC_SNAP_DUMPSYS")"
		if printf '%s\n' "$_QSC_SNAP_DUMPSYS" | egrep -q 'powered: true'; then
			QSC_BATTERY_POWERED="powered: true"
		fi
		QSC_BATTERY_STATUS="$(printf '%s\n' "$_QSC_SNAP_DUMPSYS" |
			egrep 'status: ' | sed -n 's/.*status: //g;$p')"
		_QSC_SNAP_TEMP_RAW="$(printf '%s\n' "$_QSC_SNAP_DUMPSYS" |
			egrep 'temperature: ' | sed -n 's/.*temperature: //g;$p')"
		QSC_BATTERY_TEMP="$(qsc_normalize_temperature "$_QSC_SNAP_TEMP_RAW")"
		[ -n "$QSC_BATTERY_SOURCE" ] || QSC_BATTERY_SOURCE="dumpsys"
	fi

	# dumpsys 的字段可能不完整，仍按同一优先级补齐 sysfs。
	[ -n "$QSC_BATTERY_LEVEL" ] && : || QSC_BATTERY_LEVEL="$_QSC_SNAP_CAP"
	[ -n "$QSC_BATTERY_TEMP" ] && : || QSC_BATTERY_TEMP="$_QSC_SNAP_TEMP"
	if [ -z "$QSC_BATTERY_STATUS" ]; then
		case "$_QSC_SNAP_STATUS" in
			Charging) QSC_BATTERY_STATUS=2; QSC_BATTERY_POWERED="powered: true" ;;
			Full) QSC_BATTERY_STATUS=5; QSC_BATTERY_POWERED="powered: true" ;;
			Discharging) QSC_BATTERY_STATUS=3 ;;
			"Not charging") QSC_BATTERY_STATUS=4 ;;
		esac
	fi
	if [ -z "$QSC_BATTERY_POWERED" ] && qsc_ps_plugged; then
		QSC_BATTERY_POWERED="powered: true"
		[ "$QSC_BATTERY_STATUS" = "3" ] && QSC_BATTERY_STATUS=2
	fi
	QSC_BATTERY_READ_AT="$(date +%s 2>/dev/null)"
	[ -n "$QSC_BATTERY_SOURCE" ] || QSC_BATTERY_SOURCE="fallback"
	[ -n "$QSC_BATTERY_LEVEL" ] && [ -n "$QSC_BATTERY_TEMP" ] &&
		[ -n "$QSC_BATTERY_STATUS" ]
}

qsc_battery_snapshot_print() {
	qsc_battery_snapshot_read >/dev/null 2>&1 || true
	printf 'level=%s\n' "$QSC_BATTERY_LEVEL"
	printf 'temp=%s\n' "$QSC_BATTERY_TEMP"
	printf 'status=%s\n' "$QSC_BATTERY_STATUS"
	printf 'powered=%s\n' "$([ -n "$QSC_BATTERY_POWERED" ] && echo 1 || echo 0)"
	printf 'source=%s\n' "$QSC_BATTERY_SOURCE"
	printf 'read_at=%s\n' "$QSC_BATTERY_READ_AT"
}

qsc_battery_snapshot_record() {
	local source="${QSC_BATTERY_SOURCE:-unavailable}" now last old_sig sig
	now="${QSC_BATTERY_READ_AT:-$(date +%s 2>/dev/null)}"
	case "$now" in ""|*[!0-9]*) return 0 ;; esac
	last="$(qsc_safe_cat "$DATADIR/battery_snapshot_at" 2>/dev/null | tr -d ' \r\n')"
	case "$last" in ""|*[!0-9]*) last=0 ;; esac
	sig="${QSC_BATTERY_LEVEL:-?}|${QSC_BATTERY_TEMP:-?}|${QSC_BATTERY_STATUS:-?}|$source"
	old_sig="$(qsc_safe_cat "$DATADIR/battery_snapshot" 2>/dev/null | tr -d '\r\n')"
	if [ "$sig" != "$old_sig" ] || [ "$((now - last))" -ge 60 ] 2>/dev/null; then
		printf '%s\n' "$sig" >"$DATADIR/battery_snapshot" 2>/dev/null
		printf '%s\n' "$now" >"$DATADIR/battery_snapshot_at" 2>/dev/null
		if [ "$source" = "unavailable" ]; then
			printf '%s\n' "incomplete" >"$DATADIR/battery_snapshot_error" 2>/dev/null
		else
			rm -f "$DATADIR/battery_snapshot_error" 2>/dev/null
		fi
	fi
}

# 直接执行本文件时为 WebUI/Action 提供稳定的 KEY=VALUE 接口。
case "${1:-}" in
	print) qsc_battery_snapshot_print ;;
esac
