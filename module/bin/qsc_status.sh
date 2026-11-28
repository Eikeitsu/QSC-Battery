#!/system/bin/sh
# APP / WebUI 共用的状态快照输出。分段标记: __QSC_*__
# 故意不 source 整份 common.sh（会拉 charge/history/省电等），轮询否则易卡 WebUI 桥。
MODDIR="${MODDIR:-/data/adb/modules/QSC_Battery}"
case "$MODDIR" in
	*/bin) MODDIR="${MODDIR%/*}" ;;
esac
BINDIR="$MODDIR/bin"
LIBDIR="$BINDIR/lib"
DATADIR="$MODDIR/data"
PSDIR="${QSC_SYSFS_ROOT:-}/sys/class/power_supply"

# shellcheck disable=SC1090
[ -f "$LIBDIR/util.sh" ] && . "$LIBDIR/util.sh"
# 插电判定：须有 qsc_ps_plugged。只拉 core+plugged，不 source 整份 common
# （否则 MCA 停充后 status=Discharging、dumpsys powered=false → 首页假「未插电」）。
# shellcheck disable=SC1090
[ -f "$LIBDIR/power_saver_core.sh" ] && . "$LIBDIR/power_saver_core.sh"
# shellcheck disable=SC1090
[ -f "$LIBDIR/power_saver_plugged.sh" ] && . "$LIBDIR/power_saver_plugged.sh"
# shellcheck disable=SC1090
[ -f "$LIBDIR/battery_snapshot.sh" ] && . "$LIBDIR/battery_snapshot.sh"

_qsc_status_print_snapshot() {
	printf '__QSC_SNAPSHOT__\n'
	if type qsc_battery_snapshot_print >/dev/null 2>&1; then
		qsc_battery_snapshot_print
	else
		echo "level=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
		echo "temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)"
		echo "status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
		# battery/online 在 MCA 停充时常空；粗判 usb/ucsi + VBUS
		_pl=0
		_bo="$(cat /sys/class/power_supply/battery/online 2>/dev/null | tr -d ' \r\n')"
		[ "$_bo" = "1" ] && _pl=1
		if [ "$_pl" != "1" ]; then
			_uo="$(cat /sys/class/power_supply/usb/online 2>/dev/null | tr -d ' \r\n')"
			_up="$(cat /sys/class/power_supply/usb/present 2>/dev/null | tr -d ' \r\n')"
			_uv="$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null | tr -d ' \r\n-')"
			_uc="$(cat /sys/class/power_supply/ucsi-source-psy*/online 2>/dev/null | head -n1 | tr -d ' \r\n')"
			case "$_uo$_uc" in *1*) _pl=1 ;; esac
			if [ "$_pl" != "1" ] && [ "$_up" = "1" ]; then
				case "$_uv" in
					""|*[!0-9]*) ;;
					*)
						if [ "$_uv" -gt 3000000 ] 2>/dev/null ||
							{ [ "$_uv" -gt 3000 ] 2>/dev/null && [ "$_uv" -lt 100000 ] 2>/dev/null; }; then
							_pl=1
						fi
						;;
				esac
			fi
		fi
		echo "plugged=$_pl"
	fi
}

# WebUI 仅需快照时：`qsc_status.sh snapshot`（更少 IO）
case "${1:-}" in
	snapshot)
		_qsc_status_print_snapshot
		exit 0
		;;
esac

_qsc_status_print_snapshot

printf '__QSC_MODULE_OFF__\n'
if [ -f "$DATADIR/module_off" ] || [ -f "$MODDIR/disable" ]; then
	echo 1
else
	echo 0
fi

printf '__QSC_CHARGING_STOPPED__\n'
if [ -f "$DATADIR/power_switch" ]; then
	echo 1
else
	echo 0
fi

printf '__QSC_DESCRIPTION__\n'
grep '^description=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-

printf '__QSC_VOLTAGE__\n'
cat /sys/class/power_supply/battery/voltage_now 2>/dev/null

printf '__QSC_CURRENT__\n'
cat /sys/class/power_supply/battery/current_now 2>/dev/null

printf '__QSC_VERSION__\n'
grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-

printf '__QSC_BATTERY__\n'
if [ -f "$MODDIR/bin/lib/battery_info.sh" ]; then
	sh "$MODDIR/bin/lib/battery_info.sh" 2>/dev/null
fi

printf '__QSC_FAILED__\n'
if [ -f "$DATADIR/stop_fail_hint" ] || [ -f "$DATADIR/no_node_logged" ]; then
	echo 1
else
	echo 0
fi
