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

# 音量键：复用 bin/lib/keys.sh（Magisk 已解压到 MODPATH）
MODDIR="$MODPATH"
if [ -f "$MODPATH/bin/common.sh" ]; then
	# shellcheck disable=SC1090
	. "$MODPATH/bin/common.sh"
else
	qsc_abort "缺少 bin/common.sh，安装包不完整"
fi

qsc_conf_value() {
	local file="$1"
	local key="$2"
	local count value
	count="$(grep -c "^${key}=" "$file" 2>/dev/null)"
	[ "$count" = "1" ] || return 1
	value="$(sed -n "s/^${key}=//p" "$file" | tr -d ' \r\n')"
	case "$value" in ""|*[!0-9]*) return 1 ;; esac
	echo "$value"
}

qsc_merge_config() {
	local source="$1"
	local target="$2"
	local merged="${target}.merge.$$"
	local default_power_stop default_power_start default_power_stop_time
	local default_charge_full default_power_reset default_temperature_switch
	local default_temperature_stop default_temperature_start
	local power_stop power_start power_stop_time charge_full power_reset
	local temperature_switch temperature_stop temperature_start value

	default_power_stop="$(qsc_conf_value "$target" power_stop)" || return 1
	default_power_start="$(qsc_conf_value "$target" power_start)" || return 1
	default_power_stop_time="$(qsc_conf_value "$target" power_stop_time)" || return 1
	default_charge_full="$(qsc_conf_value "$target" charge_full)" || return 1
	default_power_reset="$(qsc_conf_value "$target" power_reset)" || return 1
	default_temperature_switch="$(qsc_conf_value "$target" temperature_switch)" || return 1
	default_temperature_stop="$(qsc_conf_value "$target" temperature_switch_stop)" || return 1
	default_temperature_start="$(qsc_conf_value "$target" temperature_switch_start)" || return 1

	power_stop="$default_power_stop"
	power_start="$default_power_start"
	power_stop_time="$default_power_stop_time"
	charge_full="$default_charge_full"
	power_reset="$default_power_reset"
	temperature_switch="$default_temperature_switch"
	temperature_stop="$default_temperature_stop"
	temperature_start="$default_temperature_start"

	value="$(qsc_conf_value "$source" power_stop)" && [ "$value" -ge 1 -a "$value" -le 110 ] && power_stop="$value"
	value="$(qsc_conf_value "$source" power_start)" && [ "$value" -ge 0 -a "$value" -le 109 ] && power_start="$value"
	value="$(qsc_conf_value "$source" power_stop_time)" && [ "$value" -ge 1 -a "$value" -le 3600 ] && power_stop_time="$value"
	value="$(qsc_conf_value "$source" charge_full)" && [ "$value" -le 1 ] && charge_full="$value"
	value="$(qsc_conf_value "$source" power_reset)" && [ "$value" -le 1 ] && power_reset="$value"
	value="$(qsc_conf_value "$source" temperature_switch)" && [ "$value" -le 1 ] && temperature_switch="$value"
	value="$(qsc_conf_value "$source" temperature_switch_stop)" && [ "$value" -le 100 ] && temperature_stop="$value"
	value="$(qsc_conf_value "$source" temperature_switch_start)" && [ "$value" -le 100 ] && temperature_start="$value"

	if [ "$power_stop" != "110" ] && [ "$power_stop" -le "$power_start" ]; then
		power_stop="$default_power_stop"
		power_start="$default_power_start"
		ui_print "- 旧版电量阈值关系无效，已保留新版默认值"
	fi
	if [ "$temperature_stop" -le "$temperature_start" ]; then
		temperature_stop="$default_temperature_stop"
		temperature_start="$default_temperature_start"
		ui_print "- 旧版温控阈值关系无效，已保留新版默认值"
	fi

	cp -f "$target" "$merged" 2>/dev/null || return 1
	sed -i \
		-e "s/^power_stop=.*/power_stop=$power_stop/" \
		-e "s/^power_start=.*/power_start=$power_start/" \
		-e "s/^power_stop_time=.*/power_stop_time=$power_stop_time/" \
		-e "s/^charge_full=.*/charge_full=$charge_full/" \
		-e "s/^power_reset=.*/power_reset=$power_reset/" \
		-e "s/^temperature_switch=.*/temperature_switch=$temperature_switch/" \
		-e "s/^temperature_switch_stop=.*/temperature_switch_stop=$temperature_stop/" \
		-e "s/^temperature_switch_start=.*/temperature_switch_start=$temperature_start/" \
		"$merged" || {
		rm -f "$merged"
		return 1
	}
	mv -f "$merged" "$target"
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
if [ -f "$CURRENT_CONF" ] && [ ! -L "$CURRENT_CONF" ]; then
	CONFIG_SIZE="$(wc -c <"$CURRENT_CONF" 2>/dev/null | tr -d ' ')"
	case "$CONFIG_SIZE" in ""|*[!0-9]*) CONFIG_SIZE=0 ;; esac
	if [ "$CONFIG_SIZE" -gt 0 -a "$CONFIG_SIZE" -le 65536 ]; then
		cp -f "$CURRENT_CONF" "$CONFIG_BACKUP" 2>/dev/null || qsc_abort "无法备份当前配置，已取消更新"
	else
		ui_print "- 旧配置大小异常，将使用新版默认配置"
	fi
fi
if [ -f "$CONFIG_BACKUP" ]; then
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
	qsc_merge_config "$CONFIG_BACKUP" "$MODPATH/config/config.conf" || qsc_abort "安全迁移原有配置失败，已取消更新"
	ui_print "- 原有有效配置已安全迁移到新版模板"
fi
rm -f "$CONFIG_BACKUP"
if [ "$INSTALL_WEBUI" != "1" ]; then
	rm -rf "$MODPATH/webroot"
fi

ui_print "--------------------------------"
ui_print " 探测本机充电控制节点..."
detect_summary="$(qsc_detect_and_write_profile)"
ui_print " $detect_summary"
ui_print " 已写入 data/device.profile"

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
ui_print " Action: 上=刷新 / 下=诊断菜单 "
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
