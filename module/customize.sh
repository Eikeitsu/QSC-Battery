#!/system/bin/sh

ui_print "********************************"
ui_print " QSC 定量停充 (QSC-Battery) "
ui_print " 原作者: top大佬 @酷安 "
ui_print " 维护: 许小墨 @酷安"
ui_print "********************************"

qsc_abort() {
	ui_print "! $1"
	if command -v abort >/dev/null 2>&1; then
		abort "$1"
	fi
	exit 1
}

# 返回：0=音量上，1=音量下，2=超时或当前环境无法读取按键。
qsc_volume_choice() {
	local event_file event_pid second
	event_file="${TMPDIR:-/data/local/tmp}/qsc-key-events.$$"
	rm -f "$event_file"

	if ! command -v getevent >/dev/null 2>&1; then
		return 2
	fi

	getevent -ql >"$event_file" 2>/dev/null &
	event_pid=$!
	for second in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
		sleep 1
		if grep -q 'KEY_VOLUMEUP.*DOWN' "$event_file" 2>/dev/null; then
			kill "$event_pid" 2>/dev/null
			wait "$event_pid" 2>/dev/null
			rm -f "$event_file"
			return 0
		fi
		if grep -q 'KEY_VOLUMEDOWN.*DOWN' "$event_file" 2>/dev/null; then
			kill "$event_pid" 2>/dev/null
			wait "$event_pid" 2>/dev/null
			rm -f "$event_file"
			return 1
		fi
	done

	kill "$event_pid" 2>/dev/null
	wait "$event_pid" 2>/dev/null
	rm -f "$event_file"
	return 2
}

ui_print "--------------------------------"
ui_print " 是否确认安装 QSC 定量停充？"
ui_print " 音量上：确认安装"
ui_print " 音量下：取消安装"
ui_print " 请在 20 秒内选择"
qsc_volume_choice
case "$?" in
	0) ui_print "- 已确认安装" ;;
	1) qsc_abort "用户取消安装" ;;
	*) qsc_abort "等待安装确认超时，已安全取消" ;;
esac

KEEP_CONFIG=0
CURRENT_MODULE="/data/adb/modules/QSC_Battery"
CURRENT_CONF="$CURRENT_MODULE/config/config.conf"
CONFIG_BACKUP="${TMPDIR:-/data/local/tmp}/qsc-config-backup.$$"
rm -f "$CONFIG_BACKUP"
if [ -f "$CURRENT_CONF" ]; then
	cp -f "$CURRENT_CONF" "$CONFIG_BACKUP" 2>/dev/null || qsc_abort "无法备份当前配置，已取消更新"
	ui_print "--------------------------------"
	ui_print " 检测到已安装的 QSC-Battery"
	ui_print " 音量上：保留原有配置"
	ui_print " 音量下：使用新版默认配置"
	ui_print " 20 秒未选择时自动保留原有配置"
	qsc_volume_choice
	case "$?" in
		0) KEEP_CONFIG=1; ui_print "- 将保留原有配置" ;;
		1) ui_print "- 将使用新版默认配置" ;;
		*) KEEP_CONFIG=1; ui_print "- 选择超时，按安全默认保留原有配置" ;;
	esac
fi

INSTALL_WEBUI=1
ui_print "--------------------------------"
ui_print " 是否安装 WebUI？"
ui_print " 音量上：安装 WebUI"
ui_print " 音量下：不安装 WebUI"
ui_print " 20 秒未选择时默认安装 WebUI"
qsc_volume_choice
case "$?" in
	0) ui_print "- 将安装 WebUI" ;;
	1) INSTALL_WEBUI=0; ui_print "- 将不安装 WebUI" ;;
	*) ui_print "- 选择超时，默认安装 WebUI" ;;
esac

# 旧版模块 id（更名前）；检测到则自动卸载，不再做文件迁移
# 原作无 uninstall.sh，也不做充电节点兜底：安装后需重启，内核会复位 sysfs
OLD_MODULE_IDS="QuantitativeStopCharging_switch"
OLD_FOUND=0

qsc_uninstall_old_module() {
	local old_id="$1"
	local base path

	for base in /data/adb/modules /data/adb/modules_update; do
		path="$base/$old_id"
		[ -d "$path" ] || continue
		# 跳过当前正在安装的新模块目录
		[ "$path" = "$MODPATH" ] && continue

		OLD_FOUND=1
		ui_print "--------------------------------"
		ui_print " 检测到旧版模块: $old_id"
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
			ui_print " 旧版目录未能立即删除，已标记重启后移除"
		else
			ui_print " 已卸载旧版模块: $old_id"
		fi
	done
}

ui_print "--------------------------------"
ui_print " 检查是否已安装旧版模块..."
for old_id in $OLD_MODULE_IDS; do
	qsc_uninstall_old_module "$old_id"
done

if [ "$OLD_FOUND" = "0" ]; then
	ui_print " 未检测到旧版模块，按全新安装继续"
else
	ui_print "--------------------------------"
	ui_print " 说明: 模块 id 已变更为 QSC_Battery"
	ui_print " 旧版 QuantitativeStopCharging_switch"
	ui_print " 已被自动卸载，配置不会自动带入"
fi

cp "$MODPATH/module.prop" "$MODPATH/t_module"
mkdir -p "$MODPATH/bin" "$MODPATH/config" "$MODPATH/data" "$MODPATH/webroot"
if [ "$KEEP_CONFIG" = "1" ]; then
	cp -f "$CONFIG_BACKUP" "$MODPATH/config/config.conf" 2>/dev/null || qsc_abort "恢复原有配置失败，已取消更新"
	ui_print "- 原有 config/config.conf 已恢复"
fi
rm -f "$CONFIG_BACKUP"
if [ "$INSTALL_WEBUI" != "1" ]; then
	rm -rf "$MODPATH/webroot"
fi

ui_print "--------------------------------"
ui_print " 目录结构: "
ui_print "  bin/     核心脚本 "
ui_print "  config/  用户配置 "
ui_print "  data/    运行数据 "
[ "$INSTALL_WEBUI" = "1" ] && ui_print "  webroot/ WebUI 界面 "
ui_print "--------------------------------"
if [ "$INSTALL_WEBUI" = "1" ]; then
	ui_print " 安装后可在 Magisk/KernelSU 打开 WebUI "
else
	ui_print " 本次未安装 WebUI，可直接编辑配置文件 "
fi
ui_print " 配置: config/config.conf "
ui_print " 日志: data/log.log "
ui_print "--------------------------------"
ui_print " 安装完成，请重启设备 "
ui_print "********************************"

set_perm_recursive "$MODPATH/bin" root root 0755 0755
set_perm_recursive "$MODPATH/config" root root 0755 0644
set_perm_recursive "$MODPATH/data" root root 0755 0777
[ -d "$MODPATH/assets" ] && set_perm_recursive "$MODPATH/assets" root root 0755 0644
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" root root 0755 0644
set_perm "$MODPATH/service.sh" root root 0755
set_perm "$MODPATH/uninstall.sh" root root 0755
set_perm "$MODPATH/action.sh" root root 0755
set_perm "$MODPATH/customize.sh" root root 0755
