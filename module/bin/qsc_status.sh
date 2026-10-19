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
		echo "plugged=$(cat /sys/class/power_supply/battery/online 2>/dev/null)"
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
