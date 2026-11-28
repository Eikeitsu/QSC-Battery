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
			# 不在此直接认「已插电」：部分机型（如一加）未插电仍报 Charging
			;;
		Full)
			QSC_BATTERY_STATUS=5
			;;
		Discharging)
			QSC_BATTERY_STATUS=3
			;;
		"Not charging")
			QSC_BATTERY_STATUS=4
			;;
	esac

	# 插电以 qsc_ps_plugged（端口/电流交叉）为准。
	# K90U/MCA 充电时常 online=0、掉 VBUS；若端口扫描漏判，仅在有
	# 「充电态 + 大电流 / present / Charging|Full」旁证时才用 dumpsys 补正，
	# 禁止单靠 Not charging + dumpsys powered 假插电（过夜掉电根因）。
	if type qsc_ps_plugged >/dev/null 2>&1; then
		if qsc_ps_plugged; then
			QSC_BATTERY_POWERED="powered: true"
		else
			QSC_BATTERY_POWERED=""
		fi
	else
		# 轻量调用方（旧 qsc_status）未加载 plugged：用 usb/ucsi + VBUS 兜底，
		# 避免 MCA 停充 Discharging 时首页假「未插电」。
		_snap_uv="$(cat "$PSDIR/usb/voltage_now" 2>/dev/null | tr -d ' \r\n-')"
		_snap_up="$(cat "$PSDIR/usb/present" 2>/dev/null | tr -d ' \r\n')"
		_snap_uo="$(cat "$PSDIR/usb/online" 2>/dev/null | tr -d ' \r\n')"
		_snap_uc="$(cat "$PSDIR"/ucsi-source-psy*/online 2>/dev/null | head -n1 | tr -d ' \r\n')"
		case "$_snap_uo$_snap_uc" in *1*) QSC_BATTERY_POWERED="powered: true" ;; esac
		if [ -z "$QSC_BATTERY_POWERED" ] && [ "$_snap_up" = "1" ]; then
			case "$_snap_uv" in
				""|*[!0-9]*) ;;
				*)
					if [ "$_snap_uv" -gt 3000000 ] 2>/dev/null ||
						{ [ "$_snap_uv" -gt 3000 ] 2>/dev/null && [ "$_snap_uv" -lt 100000 ] 2>/dev/null; }; then
						QSC_BATTERY_POWERED="powered: true"
					fi
					;;
			esac
		fi
	fi

	if [ -z "$QSC_BATTERY_POWERED" ] && command -v dumpsys >/dev/null 2>&1; then
		_snap_need_ds=0
		case "${QSC_BATTERY_STATUS:-}" in
			2|5) _snap_need_ds=1 ;; # Charging / Full
			4)
				# Not charging：必须另有电流/present 旁证
				if type qsc_ps_charging_current_live >/dev/null 2>&1 &&
					qsc_ps_charging_current_live; then
					_snap_need_ds=1
				elif qsc_read_node "$PSDIR/usb/present" 2>/dev/null &&
					[ "$QSC_NODE_VAL" = "1" ]; then
					_snap_need_ds=1
				elif qsc_read_node "$PSDIR/qc_usb/present" 2>/dev/null &&
					[ "$QSC_NODE_VAL" = "1" ]; then
					_snap_need_ds=1
				fi
				;;
		esac
		if [ "$_snap_need_ds" = "1" ] &&
			dumpsys battery 2>/dev/null | egrep -q 'powered: true'; then
			QSC_BATTERY_POWERED="powered: true"
		fi
	fi

	# 完整 sysfs：返回前再与 qsc_ps_plugged 对齐一次（防止 dumpsys 单独撒谎）
	if [ -n "$_QSC_SNAP_CAP" ] && [ -n "$QSC_BATTERY_STATUS" ] &&
		[ -n "$_QSC_SNAP_TEMP" ]; then
		if [ -n "$QSC_BATTERY_POWERED" ] &&
			type qsc_ps_plugged >/dev/null 2>&1 && ! qsc_ps_plugged; then
			# dumpsys 说有电但端口扫描仍否：保留 powered 仅当有大电流/充电态旁证
			_keep=0
			type qsc_ps_charging_current_live >/dev/null 2>&1 &&
				qsc_ps_charging_current_live && _keep=1
			case "${QSC_BATTERY_STATUS:-}" in
				2|5) [ "$_keep" = "1" ] || _keep=1 ;; # Charging/Full 信任 dumpsys+status
			esac
			# status=4 且无大电流：清掉，避免未插电假插电
			if [ "${QSC_BATTERY_STATUS:-}" = "4" ] && [ "$_keep" != "1" ]; then
				QSC_BATTERY_POWERED=""
			fi
		fi
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
			Charging) QSC_BATTERY_STATUS=2 ;;
			Full) QSC_BATTERY_STATUS=5 ;;
			Discharging) QSC_BATTERY_STATUS=3 ;;
			"Not charging") QSC_BATTERY_STATUS=4 ;;
		esac
	else
		# dumpsys 可能仍是英文 status，归一成与 sysfs 一致的数字。
		# 先匹配含 Discharging 的串，再匹配 Charging（否则 *"Charging"* 会误吃 Discharging）。
		_st_norm="$(printf '%s' "$QSC_BATTERY_STATUS" | tr -d ' \r\n')"
		case "$_st_norm" in
			2|3|4|5) ;;
			Charging|charging) QSC_BATTERY_STATUS=2 ;;
			Full|full) QSC_BATTERY_STATUS=5 ;;
			Discharging|discharging) QSC_BATTERY_STATUS=3 ;;
			Notcharging|not_charging|NotCharging) QSC_BATTERY_STATUS=4 ;;
			1) QSC_BATTERY_STATUS=1 ;;
			*)
				case "$_st_norm" in
					*"Notcharging"*|*"not_charging"*|*"NotCharging"*) QSC_BATTERY_STATUS=4 ;;
					*"Discharging"*|*"discharging"*) QSC_BATTERY_STATUS=3 ;;
					*"Charging"*|*"charging"*) QSC_BATTERY_STATUS=2 ;;
					*"Full"*|*"full"*) QSC_BATTERY_STATUS=5 ;;
				esac
				;;
		esac
	fi
	# 插电以端口交叉判定为准：勿仅凭 status=Charging；一加等机型
	# dumpsys 也可能误报 powered:true，无 online/present 证据时清掉。
	if type qsc_ps_plugged >/dev/null 2>&1; then
		if qsc_ps_plugged; then
			QSC_BATTERY_POWERED="powered: true"
		else
			QSC_BATTERY_POWERED=""
		fi
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

# 直接执行本文件时为 apps/webui/Action 提供稳定的 KEY=VALUE 接口。
case "${1:-}" in
	print) qsc_battery_snapshot_print ;;
esac
