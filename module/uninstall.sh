#!/system/bin/sh

MODDIR=${0%/*}

# 卸载前尝试恢复充电（若模块曾触发停充）
if [ -f "$MODDIR/data/power_switch" ] && [ -f "$MODDIR/bin/common.sh" ]; then
	. "$MODDIR/bin/common.sh" 2>/dev/null
	qsc_restore_switches_from_list 2>/dev/null || true
	qsc_restore_mca_charge 2>/dev/null || true
fi

echo "$(date +%F_%T) 模块已卸载" >> /sdcard/qsc_uninstall.log 2>/dev/null
