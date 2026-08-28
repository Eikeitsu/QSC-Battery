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

# 清理免重启更新产生的外部副本、worker、锁和模块专属暂存。
# 不使用通配的 modules_update 清理，避免影响其它模块。
command -v pkill >/dev/null 2>&1 && pkill -f '/data/adb/.qsc_hot_update.sh' 2>/dev/null
rm -rf \
	/data/adb/.qsc_hot_update_payload \
	/data/adb/.qsc_hot_update.sh \
	/data/adb/.QSC_Battery.hot_update.lock \
	/data/adb/modules_update/QSC_Battery 2>/dev/null
rm -f "$MODDIR/update" 2>/dev/null

echo "$(date +%F_%T) 模块已卸载" >> /sdcard/qsc_uninstall.log 2>/dev/null
