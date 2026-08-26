#!/system/bin/sh

ui_print "********************************"
ui_print " 充电控制 (QSC-Battery) "
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
if [ -f "$LIBDIR/keys.sh" ]; then
	# shellcheck disable=SC1090
	. "$LIBDIR/keys.sh"
else
	qsc_abort "缺少 bin/lib/keys.sh，安装包不完整"
fi

# 纯数字配置项
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

# 允许 0/1/auto 等简短标记（非纯数字）
qsc_conf_token() {
	local file="$1"
	local key="$2"
	local count value
	count="$(grep -c "^${key}=" "$file" 2>/dev/null)"
	[ "$count" = "1" ] || return 1
	value="$(sed -n "s/^${key}=//p" "$file" | tr -d ' \r\n')"
	case "$value" in
		""|*[!0-9A-Za-z._:-]*) return 1 ;;
	esac
	echo "$value"
}

qsc_merge_config() {
	local source="$1"
	local target="$2"
	local merged="${target}.merge.$$"
	local default_power_stop default_power_start default_power_stop_time
	local default_charge_full default_power_reset default_compatibility_mode
	local default_temperature_switch
	local default_temperature_stop default_temperature_start
	local default_stop_hold default_notify
	local power_stop power_start power_stop_time charge_full power_reset
	local Compatibility_mode
	local temperature_switch temperature_stop temperature_start
	local stop_hold_wakelock notify_charge_event notify_kinds value _kinds

	default_power_stop="$(qsc_conf_value "$target" power_stop)" || return 1
	default_power_start="$(qsc_conf_value "$target" power_start)" || return 1
	default_power_stop_time="$(qsc_conf_value "$target" power_stop_time)" || return 1
	default_charge_full="$(qsc_conf_value "$target" charge_full)" || return 1
	default_power_reset="$(qsc_conf_value "$target" power_reset)" || return 1
	default_compatibility_mode="$(qsc_conf_value "$target" Compatibility_mode)" || default_compatibility_mode=0
	default_temperature_switch="$(qsc_conf_value "$target" temperature_switch)" || return 1
	default_temperature_stop="$(qsc_conf_value "$target" temperature_switch_stop)" || return 1
	default_temperature_start="$(qsc_conf_value "$target" temperature_switch_start)" || return 1
	default_stop_hold="$(qsc_conf_token "$target" stop_hold_wakelock)" || default_stop_hold=auto
	default_notify="$(qsc_conf_value "$target" notify_charge_event)" || default_notify=0
	notify_kinds="$(sed -n 's/^notify_charge_kinds=//p' "$target" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	[ -n "$notify_kinds" ] || notify_kinds="stop,resume,fail"

	power_stop="$default_power_stop"
	power_start="$default_power_start"
	power_stop_time="$default_power_stop_time"
	charge_full="$default_charge_full"
	power_reset="$default_power_reset"
	Compatibility_mode="$default_compatibility_mode"
	temperature_switch="$default_temperature_switch"
	temperature_stop="$default_temperature_stop"
	temperature_start="$default_temperature_start"
	stop_hold_wakelock="$default_stop_hold"
	notify_charge_event="$default_notify"

	value="$(qsc_conf_value "$source" power_stop)" && [ "$value" -ge 1 -a "$value" -le 110 ] && power_stop="$value"
	value="$(qsc_conf_value "$source" power_start)" && [ "$value" -ge 0 -a "$value" -le 109 ] && power_start="$value"
	value="$(qsc_conf_value "$source" power_stop_time)" && [ "$value" -ge 1 -a "$value" -le 3600 ] && power_stop_time="$value"
	value="$(qsc_conf_value "$source" charge_full)" && [ "$value" -le 1 ] && charge_full="$value"
	value="$(qsc_conf_value "$source" power_reset)" && [ "$value" -le 1 ] && power_reset="$value"
	value="$(qsc_conf_value "$source" Compatibility_mode)" && [ "$value" -le 1 ] && Compatibility_mode="$value"
	value="$(qsc_conf_value "$source" temperature_switch)" && [ "$value" -le 1 ] && temperature_switch="$value"
	value="$(qsc_conf_value "$source" temperature_switch_stop)" && [ "$value" -le 100 ] && temperature_stop="$value"
	value="$(qsc_conf_value "$source" temperature_switch_start)" && [ "$value" -le 100 ] && temperature_start="$value"
	value="$(qsc_conf_token "$source" stop_hold_wakelock)" && case "$value" in 0|1|auto) stop_hold_wakelock="$value" ;; esac
	value="$(qsc_conf_value "$source" notify_charge_event)" && [ "$value" -le 1 ] && notify_charge_event="$value"
	# notify_charge_kinds 允许逗号列表
	_kinds="$(sed -n 's/^notify_charge_kinds=//p' "$source" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	case "$_kinds" in
		""|*[^a-z,]*) ;;
		*)
			notify_kinds="$_kinds"
			;;
	esac

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
		-e "s/^Compatibility_mode=.*/Compatibility_mode=$Compatibility_mode/" \
		-e "s/^stop_hold_wakelock=.*/stop_hold_wakelock=$stop_hold_wakelock/" \
		-e "s/^notify_charge_event=.*/notify_charge_event=$notify_charge_event/" \
		-e "s/^notify_charge_kinds=.*/notify_charge_kinds=$notify_kinds/" \
		-e "s/^temperature_switch=.*/temperature_switch=$temperature_switch/" \
		-e "s/^temperature_switch_stop=.*/temperature_switch_stop=$temperature_stop/" \
		-e "s/^temperature_switch_start=.*/temperature_switch_start=$temperature_start/" \
		"$merged" || {
		rm -f "$merged"
		return 1
	}
	# 迁移新增标量键（有则覆盖模板默认）
	for _nk in loop_interval_sec loop_interval_maintain_sec switch_verify_sec \
		wireless_policy history_enable history_interval_sec app_stop app_stop_list; do
		_nv="$(sed -n "s/^${_nk}=//p" "$source" 2>/dev/null | head -n1 | tr -d '\r')"
		[ -n "$_nv" ] || continue
		if grep -q "^${_nk}=" "$merged" 2>/dev/null; then
			sed -i "s|^${_nk}=.*|${_nk}=${_nv}|" "$merged"
		else
			echo "${_nk}=${_nv}" >>"$merged"
		fi
	done
	# 迁移用户自定义供电开关与停充时段（多行）；跳过策略类节点以免闪充
	sed -i -e '/^power_switch=/d' -e '/^power_stop_schedule=/d' -e '/^notify_quiet_schedule=/d' "$merged" 2>/dev/null
	if grep -q '^power_switch=' "$source" 2>/dev/null; then
		kept_ps=0
		skip_ps=0
		while IFS= read -r _ps_line || [ -n "$_ps_line" ]; do
			[ -n "$_ps_line" ] || continue
			case "$_ps_line" in
				*night_charging*|*cool_mode*|*batt_protect*|*smart_charging*|*adapter_cc_mode*|*step_charging*|*restrict_chg*|*restricted_charging*|*charge_control_*)
					skip_ps=$((skip_ps + 1))
					continue
					;;
			esac
			echo "$_ps_line" >>"$merged"
			kept_ps=$((kept_ps + 1))
		done <<EOF
$(grep '^power_switch=' "$source" 2>/dev/null)
EOF
		if [ "$kept_ps" -gt 0 ]; then
			ui_print "- 已迁移自定义 power_switch（${kept_ps} 条）"
		fi
		if [ "$skip_ps" -gt 0 ]; then
			ui_print "- 已跳过 ${skip_ps} 条策略类 power_switch（易导致闪充）"
		fi
	fi
	if grep -q '^power_stop_schedule=' "$source" 2>/dev/null; then
		grep '^power_stop_schedule=' "$source" >>"$merged" 2>/dev/null
		ui_print "- 已迁移停充时段 power_stop_schedule"
	fi
	if grep -q '^notify_quiet_schedule=' "$source" 2>/dev/null; then
		grep '^notify_quiet_schedule=' "$source" >>"$merged" 2>/dev/null
		ui_print "- 已迁移通知勿扰时段"
	fi
	mv -f "$merged" "$target"
}

ui_print "--------------------------------"
ui_print " 是否确认安装 充电控制？"
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
CURRENT_JSON="$CURRENT_MODULE/config/current.json"
CONFIG_BACKUP="${TMPDIR:-/data/local/tmp}/qsc-config-backup.$$"
CURRENT_JSON_BACKUP="${TMPDIR:-/data/local/tmp}/qsc-current-json-backup.$$"
rm -f "$CONFIG_BACKUP" "$CURRENT_JSON_BACKUP"
if [ -f "$CURRENT_CONF" ] && [ ! -L "$CURRENT_CONF" ]; then
	CONFIG_SIZE="$(wc -c <"$CURRENT_CONF" 2>/dev/null | tr -d ' ')"
	case "$CONFIG_SIZE" in ""|*[!0-9]*) CONFIG_SIZE=0 ;; esac
	if [ "$CONFIG_SIZE" -gt 0 -a "$CONFIG_SIZE" -le 65536 ]; then
		cp -f "$CURRENT_CONF" "$CONFIG_BACKUP" 2>/dev/null || qsc_abort "无法备份当前配置，已取消更新"
	else
		ui_print "- 旧配置大小异常，将使用新版默认配置"
	fi
fi
if [ -f "$CURRENT_JSON" ] && [ ! -L "$CURRENT_JSON" ]; then
	cp -f "$CURRENT_JSON" "$CURRENT_JSON_BACKUP" 2>/dev/null || true
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

INSTALL_CURRENT=1
ui_print "--------------------------------"
ui_print " 是否安装「电流控制」组件？"
ui_print " （模拟旁路 / 慢充 / 限流 / 游戏限流）"
ui_print " 配置文件：config/current.json"
ui_print " 音量上：安装（默认关闭，需手动开启）"
ui_print " 音量下：不安装（不写入相关文件）"
ui_print " 20 秒未选择时默认安装"
qsc_volume_choice
case "$?" in
	0) ui_print "- 将安装电流控制组件" ;;
	1) INSTALL_CURRENT=0; ui_print "- 将不安装电流控制组件" ;;
	*) ui_print "- 选择超时，默认安装电流控制组件" ;;
esac

# 旧版模块 id；检测到则自动卸载，不再做文件迁移
# 完整版 QuantitativeStopCharging（QSC定量停充）
# 独立开关版 QuantitativeStopCharging_switch（QSC定量停充_独立开关版）
# 旧模块无 uninstall.sh，也不做充电节点兜底：安装后需重启，内核会复位 sysfs
OLD_MODULE_IDS="QuantitativeStopCharging QuantitativeStopCharging_switch"
OLD_FOUND=0
OLD_REMOVED_NAMES=""

qsc_old_module_name() {
	case "$1" in
		QuantitativeStopCharging) echo "QSC定量停充" ;;
		QuantitativeStopCharging_switch) echo "QSC定量停充_独立开关版" ;;
		*) echo "$1" ;;
	esac
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

ui_print "--------------------------------"
ui_print " 检查是否已安装旧版模块..."
ui_print " （QSC定量停充 / QSC定量停充_独立开关版）"
for old_id in $OLD_MODULE_IDS; do
	qsc_uninstall_old_module "$old_id"
done

if [ "$OLD_FOUND" = "0" ]; then
	ui_print " 未检测到旧版模块，按全新安装继续"
else
	ui_print "--------------------------------"
	ui_print " 说明: 模块 id 已变更为 QSC_Battery"
	ui_print " 已自动卸载旧版:$OLD_REMOVED_NAMES"
	ui_print " 配置不会自动带入，请重启后重新设置"
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

if [ "$INSTALL_CURRENT" = "1" ]; then
	if [ "$KEEP_CONFIG" = "1" ] && [ -f "$CURRENT_JSON_BACKUP" ]; then
		cp -f "$CURRENT_JSON_BACKUP" "$MODPATH/config/current.json" 2>/dev/null && ui_print "- 已保留电流控制配置 current.json"
	fi
	ui_print "- 已安装电流控制：config/current.json（默认关闭）"
else
	rm -f "$MODPATH/bin/lib/current.sh"
	rm -f "$MODPATH/config/current.json"
	ui_print "- 未安装电流控制：已移除相关脚本与配置"
fi
rm -f "$CURRENT_JSON_BACKUP"

ui_print "--------------------------------"
ui_print " 探测本机充电控制节点..."
detect_summary="$(qsc_detect_and_write_profile)"
ui_print " $detect_summary"
ui_print " 已写入 data/device.profile"

# 更新时保留运行数据（list / 历史 / 关闭标记等）
if [ -f "$LIBDIR/hot_update.sh" ]; then
	# shellcheck disable=SC1090
	. "$LIBDIR/hot_update.sh"
	hot_update_preserve_paths "$CURRENT_MODULE" "$MODPATH" \
		data/list_switch data/list_charge_current data/ch_curr_ctrl_files \
		data/device.profile data/charge_history.csv data/off_qsc \
		data/compat_hint
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
[ "$INSTALL_CURRENT" = "1" ] && ui_print " 电流控制: config/current.json "
ui_print " 日志: data/log.log "
ui_print " Action: 上=刷新 / 下=插电测开关(未插电则诊断) "
ui_print "--------------------------------"

set_perm_recursive "$MODPATH/bin" root root 0755 0755
set_perm_recursive "$MODPATH/config" root root 0755 0644
set_perm_recursive "$MODPATH/data" root root 0755 0777
[ -d "$MODPATH/assets" ] && set_perm_recursive "$MODPATH/assets" root root 0755 0644
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" root root 0755 0644
set_perm "$MODPATH/service.sh" root root 0755
set_perm "$MODPATH/uninstall.sh" root root 0755
set_perm "$MODPATH/action.sh" root root 0755
set_perm "$MODPATH/customize.sh" root root 0755
set_perm "$MODPATH/hotinstall.sh" root root 0755

# 非首次：本模块无 system/sepolicy 等开机挂载，更新默认可免重启
ui_print "--------------------------------"
if [ -f "$LIBDIR/hot_update.sh" ]; then
	# 无「必须重启」路径 → 空参数列表；仅首次/禁用时会要求重启
	if hot_update_try QSC_Battery; then
		ui_print " 热更新将重启充电控制服务 "
	fi
else
	ui_print " 安装完成，请重启设备 "
fi
ui_print "********************************"
