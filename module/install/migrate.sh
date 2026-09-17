#!/system/bin/sh
# old module helpers / one-shot incompatible-layout cutover

# 当前布局首版 versionCode：已装模块若低于此值，安装时强制卸净并当全新安装。
# 此后任意更高 versionCode 的更新都走正常保留配置 / 热更新，不会再次切断。
QSC_LAYOUT_CUTOVER_CODE=2026091701

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

# 若 /data/adb/modules/QSC_Battery 仍是切断线之前的安装：执行 uninstall 并删除目录。
# 不碰正在解压的 MODPATH（通常是 modules_update/QSC_Battery）。
# 返回 0 = 已切断并清空；1 = 无需切断
qsc_wipe_incompatible_module() {
	_cut_path="/data/adb/modules/QSC_Battery"
	[ -d "$_cut_path" ] || return 1
	[ "$_cut_path" = "$MODPATH" ] && return 1

	_cut_code="$(qsc_module_version_code "$_cut_path/module.prop")"
	case "$_cut_code" in
		""|*[!0-9]*)
			# 无有效 versionCode 也视为切断线前残留
			;;
		*)
			[ "$_cut_code" -ge "$QSC_LAYOUT_CUTOVER_CODE" ] 2>/dev/null && return 1
			;;
	esac

	ui_print "--------------------------------"
	ui_print " 检测到不兼容的旧版模块 (versionCode=${_cut_code:-?})"
	ui_print " 本版变更较大：将强制完整重装（不保留配置 / data / 外部 qsc）"
	ui_print " 切断阈值 versionCode=$QSC_LAYOUT_CUTOVER_CODE"

	if [ -f "$_cut_path/uninstall.sh" ]; then
		ui_print "- 执行旧模块 uninstall.sh…"
		# shellcheck disable=SC1090
		sh "$_cut_path/uninstall.sh" >/dev/null 2>&1 || true
	fi
	rm -rf "$_cut_path"
	# 外部工作区一并清空（热更新副本 / 诊断 / 旧 CLI）；install_auto 已在 customize 开头读入内存
	pkill -f '/data/adb/qsc/hot_update/worker.sh' 2>/dev/null || true
	pkill -f '/data/adb/qsc/hot_update/verify.sh' 2>/dev/null || true
	rm -rf /data/adb/qsc 2>/dev/null || true
	ui_print "- 已清空 /data/adb/qsc"
	if [ -d "$_cut_path" ]; then
		touch "$_cut_path/remove" 2>/dev/null || true
		ui_print "- 未能立即删除模块目录，已标记重启后移除"
	else
		ui_print "- 已清空旧模块目录"
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
