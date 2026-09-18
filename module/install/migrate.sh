#!/system/bin/sh
# old module helpers / one-shot clean reinstall cutover

# 完整重装切断线：已装模块 versionCode 低于此值则清空 conf/data（当全新安装）。
# 此后更高 versionCode 走正常保留配置 / 热更新。
QSC_CLEAN_CUTOVER_CODE=2026091701
# 兼容旧变量名（热更新脚本可能仍引用）
QSC_LAYOUT_CUTOVER_CODE="$QSC_CLEAN_CUTOVER_CODE"

qsc_old_module_name() {
	case "$1" in
		QuantitativeStopCharging) echo "QSC定量停充" ;;
		QuantitativeStopCharging_switch) echo "QSC定量停充_独立开关版" ;;
		*) echo "$1" ;;
	esac
}

qsc_module_version_code() {
	sed -n 's/^versionCode=//p' "$1" 2>/dev/null | head -n1 | tr -d ' \r'
}

# 若 /data/adb/modules/QSC_Battery 仍是切断线之前的安装：删掉该目录 + 外部 qsc，等同全新安装。
# 切勿跑 uninstall.sh（旧脚本会 rm modules_update）；切勿删 $MODPATH / modules_update
# （本次解压目录）。只删 modules/ 下的旧壳即可。
# 返回 0 = 已切断；1 = 无需切断

# 删目录前先停旧常驻进程，否则会继续往壳目录 module.prop 写「核心脚本丢失」。
qsc_cutover_stop_old_runtime() {
	_root="$1"
	_pid=""
	_i=0
	[ -n "$_root" ] && [ -d "$_root" ] || return 0
	for _pf in \
		"$_root/data/description_worker.pid" \
		"$_root/data/service_heartbeat_pid" \
		"$_root/data/service_pid"; do
		_pid="$(cat "$_pf" 2>/dev/null | tr -d ' \r\n')"
		case "$_pid" in
			""|*[!0-9]*) continue ;;
			*)
				kill "$_pid" 2>/dev/null || true
				_i=0
				while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt 5 ]; do
					sleep 1
					_i=$((_i + 1))
				done
				kill -9 "$_pid" 2>/dev/null || true
				;;
		esac
	done
	command -v pkill >/dev/null 2>&1 && {
		pkill -f "$_root/bin/description_worker.sh" 2>/dev/null || true
		pkill -f "$_root/bin/qsc_switch.sh" 2>/dev/null || true
		pkill -f "$_root/service.sh" 2>/dev/null || true
		pkill -f "$_root/bin/qscd" 2>/dev/null || true
		pkill -f "$_root/bin/qscd-rust" 2>/dev/null || true
		pkill -f "$_root/bin/qscd-c" 2>/dev/null || true
	}
}

qsc_wipe_incompatible_module() {
	_cut_path="/data/adb/modules/QSC_Battery"
	[ -d "$_cut_path" ] || return 1
	# 保护：当前解压目录若就是 modules 下该路径，绝不动（极少见）
	[ "$_cut_path" = "$MODPATH" ] && return 1

	_cut_code="$(qsc_module_version_code "$_cut_path/module.prop")"
	case "$_cut_code" in
		""|*[!0-9]*)
			# 无有效 versionCode 也视为切断线前残留
			;;
		*)
			[ "$_cut_code" -ge "$QSC_CLEAN_CUTOVER_CODE" ] 2>/dev/null && return 1
			;;
	esac

	ui_print "--------------------------------"
	ui_print " 检测到不兼容的旧版模块 (versionCode=${_cut_code:-?})"
	ui_print " 变更较大：将强制完整重装（不保留配置 / data / 外部 qsc）"
	ui_print " 切断阈值 versionCode=$QSC_CLEAN_CUTOVER_CODE"

	# 尽量还原停充节点；不跑 uninstall.sh（会误删 modules_update）
	if [ -f "$_cut_path/data/power_switch" ] && [ -f "$_cut_path/bin/common.sh" ]; then
		ui_print "- 尝试还原旧版停充节点…"
		(
			MODDIR="$_cut_path"
			# shellcheck disable=SC1090
			. "$_cut_path/bin/common.sh" 2>/dev/null || exit 0
			qsc_restore_switches_from_list 2>/dev/null || true
			qsc_restore_mca_charge 2>/dev/null || true
			qsc_stop_wakelock_release 2>/dev/null || true
			qsc_clear_active_switch 2>/dev/null || true
		) >/dev/null 2>&1 || true
	fi

	ui_print "- 停止旧版常驻进程（服务 / 简介 / 守护）…"
	qsc_cutover_stop_old_runtime "$_cut_path"

	# 外部工作区：清热更新/诊断/CLI；保留 install_auto；绝不碰 modules_update
	_keep_auto=0
	[ -f /data/adb/qsc/install_auto ] && _keep_auto=1
	[ "${QSC_INSTALL_AUTO:-0}" = "1" ] && _keep_auto=1
	command -v pkill >/dev/null 2>&1 && {
		pkill -f '/data/adb/qsc/hot_update/worker.sh' 2>/dev/null || true
		pkill -f '/data/adb/qsc/hot_update/verify.sh' 2>/dev/null || true
	}
	rm -rf \
		/data/adb/qsc/hot_update \
		/data/adb/qsc/runtime \
		/data/adb/.qsc_hot_update_payload \
		/data/adb/.qsc_hot_update_txn \
		/data/adb/.qsc_hot_update_verify.sh \
		/data/adb/.qsc_hot_update.sh \
		/data/adb/.QSC_Battery.hot_update.lock 2>/dev/null || true
	rm -f /data/adb/qsc/bin/qsc 2>/dev/null || true
	rmdir /data/adb/qsc/bin 2>/dev/null || true
	rmdir /data/adb/qsc 2>/dev/null || true
	if [ "$_keep_auto" = "1" ]; then
		mkdir -p /data/adb/qsc 2>/dev/null || true
		touch /data/adb/qsc/install_auto 2>/dev/null || true
	fi
	ui_print "- 已清空外部 qsc 工作区"

	# 只删旧安装目录；管理器稍后会在 modules/ 写 update 标记，重启后用 modules_update 顶替
	rm -rf "$_cut_path" 2>/dev/null || true
	if [ -d "$_cut_path" ]; then
		# 删不掉就退化为清 conf/data，仍不碰 modules_update
		rm -rf "$_cut_path/config" "$_cut_path/data" 2>/dev/null || true
		mkdir -p "$_cut_path/config" "$_cut_path/data" 2>/dev/null || true
		rm -f "$_cut_path/update" 2>/dev/null || true
		ui_print "- 旧模块目录未能删除，已清空 config/data"
	else
		ui_print "- 已删除旧模块目录（等同全新安装）"
	fi
	return 0
}

qsc_uninstall_old_module() {
	local old_id="$1"
	local old_name base path

	old_name="$(qsc_old_module_name "$old_id")"
	for base in /data/adb/modules /data/adb/modules_update; do
		path="$base/$old_id"
		[ -d "$path" ] || continue
		# 跳过当前正在安装的新模块目录
		[ "$path" = "$MODPATH" ] && continue

		OLD_FOUND=1
		case " $OLD_REMOVED_NAMES " in
			*" $old_name "*) ;;
			*) OLD_REMOVED_NAMES="$OLD_REMOVED_NAMES $old_name" ;;
		esac
		ui_print "--------------------------------"
		ui_print " 检测到旧版模块: $old_name"
		ui_print " 位置: $path"
		ui_print " 兼容策略: 自动卸载旧版（不迁移配置、不写充电节点）"
		ui_print " 请安装后重启，并在 WebUI 重新设置阈值"

		if [ -f "$path/uninstall.sh" ]; then
			ui_print " 正在执行旧版卸载脚本..."
			sh "$path/uninstall.sh" >/dev/null 2>&1 || true
		else
			ui_print " 旧版无 uninstall.sh，直接移除目录"
		fi

		rm -rf "$path"
		if [ -d "$path" ]; then
			touch "$path/remove" 2>/dev/null || true
			ui_print " 未能立即删除，已标记重启后移除: $old_name"
		else
			ui_print " 已卸载旧版模块: $old_name"
		fi
	done
}
