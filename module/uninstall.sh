#!/system/bin/sh

MODDIR=${0%/*}

# 卸载前尝试恢复充电（若模块曾触发停充）
if [ -f "$MODDIR/bin/common.sh" ]; then
	. "$MODDIR/bin/common.sh" 2>/dev/null
	if [ -f "$MODDIR/data/power_switch" ]; then
		qsc_restore_switches_from_list 2>/dev/null || true
		qsc_restore_mca_charge 2>/dev/null || true
	fi
	qsc_stop_wakelock_release 2>/dev/null || true
	qsc_clear_active_switch 2>/dev/null || true
fi

echo "$(date +%F_%T) 模块已卸载" >> /sdcard/qsc_uninstall.log 2>/dev/null
