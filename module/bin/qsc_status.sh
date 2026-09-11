#!/system/bin/sh
# APP / WebUI 共用的状态快照输出。分段标记: __QSC_*__
MODDIR="${MODDIR:-/data/adb/modules/QSC_Battery}"
DATADIR="$MODDIR/data"

if [ -f "$MODDIR/bin/common.sh" ]; then
	# shellcheck disable=SC1090
	. "$MODDIR/bin/common.sh"
fi

printf '__QSC_SNAPSHOT__\n'
if command -v qsc_battery_snapshot_print >/dev/null 2>&1; then
	qsc_battery_snapshot_print
else
	echo "level=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
	echo "temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)"
	echo "status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
	echo "plugged=$(cat /sys/class/power_supply/battery/online 2>/dev/null)"
fi

printf '__QSC_MODULE_OFF__\n'
if [ -f "$DATADIR/off_qsc" ] || [ -f "$MODDIR/disable" ]; then
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
