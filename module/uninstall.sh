#!/system/bin/sh

MODDIR=${0%/*}

qsc_uninstall_stop_description_worker() {
	local pid_file="$MODDIR/data/description_worker.pid" pid i
	pid="$(cat "$pid_file" 2>/dev/null | tr -d ' \r\n')"
	case "$pid" in
		""|*[!0-9]*) ;;
		*)
			kill "$pid" 2>/dev/null || true
			i=0
			while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 5 ]; do
				sleep 1
				i=$((i + 1))
			done
			kill -9 "$pid" 2>/dev/null || true
			;;
	esac
	rm -f "$pid_file" 2>/dev/null
	rm -rf "$MODDIR/data/.description_worker.lock" \
		"$MODDIR/data/.description.lock" 2>/dev/null
	rm -f "$MODDIR/data/description_worker.state" \
		"$MODDIR/data/description_worker.state.tmp" 2>/dev/null
}

qsc_uninstall_stop_description_worker

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

# 清理本模块免重启更新产生的外部副本、worker、锁和诊断。
# qsc 是可共享命名空间，只删除 QSC_Battery 自己的目录；若没有其它内容，
# 再逐级 rmdir，最终会删除整个 /data/adb/qsc，不留下本模块残留。
command -v pkill >/dev/null 2>&1 && {
	pkill -f '/data/adb/qsc/hot_update/worker.sh' 2>/dev/null
	pkill -f '/data/adb/qsc/hot_update/verify.sh' 2>/dev/null
	pkill -f '/data/adb/.qsc_hot_update.sh' 2>/dev/null
}
rm -rf \
	/data/adb/qsc/hot_update \
	/data/adb/qsc/runtime/diagnostics \
	/data/adb/.qsc_hot_update_payload \
	/data/adb/.qsc_hot_update_txn \
	/data/adb/.qsc_hot_update_verify.sh \
	/data/adb/.qsc_hot_update.sh \
	/data/adb/.QSC_Battery.hot_update.lock \
	/data/adb/modules_update/QSC_Battery 2>/dev/null
rmdir /data/adb/qsc/runtime/diagnostics 2>/dev/null
rmdir /data/adb/qsc/runtime 2>/dev/null
rmdir /data/adb/qsc 2>/dev/null
rm -f "$MODDIR/update" 2>/dev/null

echo "$(date +%F_%T) 模块已卸载" >> /sdcard/qsc_uninstall.log 2>/dev/null
