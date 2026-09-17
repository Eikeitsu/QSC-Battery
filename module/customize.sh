#!/system/bin/sh

ui_print "********************************"
ui_print " 充电控制 (QSC-Battery) "
ui_print " 原作者: top大佬 @酷安 "
ui_print " 维护: 许小墨 @酷安"
ui_print "********************************"


# 音量键：复用 bin/lib/keys.sh（Magisk 已解压到 MODPATH）
MODDIR="$MODPATH"

# install fragments（customize.sh 文件名冻结；helpers 需在 common 检查前提供 qsc_abort）
. "$MODPATH/install/helpers.sh"
. "$MODPATH/install/migrate.sh"
. "$MODPATH/install/qscd.sh"
. "$MODPATH/install/companion.sh"
. "$MODPATH/install/cli.sh"

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

# APP CLI / 脚本刷入：/data/adb/qsc/install_auto 或环境变量 → 跳过音量键，用安全默认
QSC_INSTALL_AUTO=0
if [ -f /data/adb/qsc/install_auto ] || [ "${QSC_NONINTERACTIVE:-}" = "1" ]; then
	QSC_INSTALL_AUTO=1
	ui_print "- 无人值守安装：跳过音量键，使用安全默认选项"
fi

ui_print "--------------------------------"
if [ "$QSC_INSTALL_AUTO" = "1" ]; then
	ui_print " 无人值守：已确认安装"
else
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
fi

KEEP_CONFIG=0
CURRENT_MODULE="/data/adb/modules/QSC_Battery"
CURRENT_CONF="$CURRENT_MODULE/config/config.conf"
CURRENT_JSON="$CURRENT_MODULE/config/current.json"
CONFIG_BACKUP="${TMPDIR:-/data/local/tmp}/qsc-config-backup.$$"
CURRENT_JSON_BACKUP="${TMPDIR:-/data/local/tmp}/qsc-current-json-backup.$$"
rm -f "$CONFIG_BACKUP" "$CURRENT_JSON_BACKUP"

# 切断线前旧版 → 清空后按全新安装（不保留旧 conf/data）
# APP / WebUI 无人值守与 Magisk 管理器走同一 customize，此处统一切断。
QSC_FORCE_CLEAN_INSTALL=0
if qsc_wipe_incompatible_module; then
	QSC_FORCE_CLEAN_INSTALL=1
	KEEP_CONFIG=0
	rm -f "$CONFIG_BACKUP" "$CURRENT_JSON_BACKUP"
	if [ "$QSC_INSTALL_AUTO" = "1" ]; then
		ui_print "- 无人值守：与旧版不兼容，已强制完整重装（不保留配置）"
	fi
fi

if [ "$QSC_FORCE_CLEAN_INSTALL" != "1" ] && [ -f "$CURRENT_CONF" ] && [ ! -L "$CURRENT_CONF" ]; then
	CONFIG_SIZE="$(wc -c <"$CURRENT_CONF" 2>/dev/null | tr -d ' ')"
	case "$CONFIG_SIZE" in ""|*[!0-9]*) CONFIG_SIZE=0 ;; esac
	if [ "$CONFIG_SIZE" -gt 0 -a "$CONFIG_SIZE" -le 65536 ]; then
		cp -f "$CURRENT_CONF" "$CONFIG_BACKUP" 2>/dev/null || qsc_abort "无法备份当前配置，已取消更新"
	else
		ui_print "- 旧配置大小异常，将使用新版默认配置"
	fi
fi
if [ "$QSC_FORCE_CLEAN_INSTALL" != "1" ] && [ -f "$CURRENT_JSON" ] && [ ! -L "$CURRENT_JSON" ]; then
	cp -f "$CURRENT_JSON" "$CURRENT_JSON_BACKUP" 2>/dev/null || true
fi
if [ -f "$CONFIG_BACKUP" ]; then
	if [ "$QSC_INSTALL_AUTO" = "1" ]; then
		KEEP_CONFIG=1
		ui_print "- 无人值守：保留核心配置"
	else
		ui_print "--------------------------------"
		ui_print " 检测到已安装的 QSC-Battery"
		ui_print " 音量上：保留核心配置（停充阈值/开关/时段等）"
		ui_print "         省电间隔等运行参数用新版默认"
		ui_print " 音量下：全部使用新版默认配置"
		ui_print " 20 秒未选择时按「保留核心配置」处理"
		qsc_volume_choice
		case "$?" in
			0) KEEP_CONFIG=1; ui_print "- 将保留核心配置，并应用新版省电默认" ;;
			1) ui_print "- 将使用新版默认配置" ;;
			*) KEEP_CONFIG=1; ui_print "- 选择超时，按安全默认保留核心配置" ;;
		esac
	fi
fi

INSTALL_WEBUI=1
if [ ! -f "$MODPATH/webroot/index.html" ]; then
	INSTALL_WEBUI=0
	ui_print "--------------------------------"
	ui_print "- 本包为 lite（无 WebUI），跳过界面安装选项"
elif [ "$QSC_INSTALL_AUTO" = "1" ]; then
	ui_print "- 无人值守：安装 WebUI"
else
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
fi

INSTALL_CURRENT=1
if [ "$QSC_INSTALL_AUTO" = "1" ]; then
	ui_print "- 无人值守：安装电流控制组件（默认关闭）"
else
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
fi

# 旧版模块 id；检测到则自动卸载，不再做文件迁移
# 完整版 QuantitativeStopCharging（QSC定量停充）
# 独立开关版 QuantitativeStopCharging_switch（QSC定量停充_独立开关版）
# 旧模块无 uninstall.sh，也不做充电节点兜底：安装后需重启，内核会复位 sysfs
OLD_MODULE_IDS="QuantitativeStopCharging QuantitativeStopCharging_switch"
OLD_FOUND=0
OLD_REMOVED_NAMES=""


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
	ui_print "- 配置迁移完成（核心保留 + 新版省电默认）"
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
	rm -f "$MODPATH/bin/lib/current.sh" "$MODPATH/bin/lib/current_limits.sh" \
		"$MODPATH/bin/lib/current_bypass.sh" "$MODPATH/bin/lib/current_apply.sh"
	rm -f "$MODPATH/config/current.json"
	ui_print "- 未安装电流控制：已移除相关脚本与配置"
fi
rm -f "$CURRENT_JSON_BACKUP"

ui_print "--------------------------------"
ui_print " 探测本机充电控制节点..."
detect_summary="$(qsc_detect_and_write_profile)"
ui_print " $detect_summary"
ui_print " 已写入 data/device.profile"

# 更新时保留运行数据（list / 历史 / 关闭标记等）；命名切断后旧目录已空，自然跳过
if [ "$QSC_FORCE_CLEAN_INSTALL" != "1" ] && [ -f "$LIBDIR/hot_update.sh" ]; then
	# shellcheck disable=SC1090
	. "$LIBDIR/hot_update.sh"
	hot_update_preserve_paths "$CURRENT_MODULE" "$MODPATH" \
		data/list_switch data/list_charge_current data/ch_curr_ctrl_files \
		data/device.profile data/charge_history.csv data/module_off \
		data/compat_hint data/native_src data/native_version
	# WebUI 下载来的守护要留住：本包（如主包）可能一个二进制都不带，
	# 冲掉就等于把用户装好的守护弄没了。自带同实现时下面会用自带的覆盖。
	hot_update_preserve_paths "$CURRENT_MODULE" "$MODPATH" bin/qscd
fi

# 事件唤醒守护：包里可能自带 Rust 版（qscd-*）、C 版（qscdc-*）、两套或一套都没有
# （主包）。按 ABI 取候选并逐个现场自检，第一个通过的装成 bin/qscd。
# 顺序由 config/config.conf 的 native_impl 决定（rust 默认 / c / off）。
# 本包不带可用候选时，沿用上一版里 WebUI 下载好的守护；两者都没有也不影响
# 功能——service.sh 会退回定时轮询。

# 本包没带守护时，问一次是否现在联网下载。
# 下载失败（超时 / 无网 / 校验不过）一律只提示，绝不阻断安装：
# 模块不装守护也能正常停充，用户随时可以在 WebUI 里再试。
qscd_offer_download() {
	_pref="$1"
	if [ "$QSC_INSTALL_AUTO" = "1" ]; then
		ui_print "- 无人值守：跳过联网下载守护（可在更新页 / WebUI 安装）"
		return 0
	fi
	ui_print "--------------------------------"
	ui_print " 本安装包未自带「事件唤醒」守护文件"
	ui_print " 它能让未插电时由充电事件唤醒，替代定时轮询，更省电"
	ui_print " 不装也不影响停充功能"
	ui_print " 音量上：现在联网下载"
	ui_print " 音量下：跳过（安装完成后可在 WebUI 里下载）"
	ui_print " 20 秒未选择时跳过"
	qsc_volume_choice
	case "$?" in
		0) ;;
		1)
			ui_print "- 已跳过：可在 WebUI「事件唤醒（守护）」里随时下载"
			return 0
			;;
		*)
			ui_print "- 选择超时，已跳过：可在 WebUI 里随时下载"
			return 0
			;;
	esac

	# 只在明确选 c 时先试 C 版，其余按默认的 Rust
	case "$_pref" in
		c) _dl_impl="c"; _dl_name="C" ;;
		*) _dl_impl="rust"; _dl_name="Rust" ;;
	esac

	ui_print "--------------------------------"
	ui_print " 下载哪套实现？两者功能完全一致，只能二选一"
	ui_print " 音量上：Rust 版（内存安全，体积略大）"
	ui_print " 音量下：C 版（依赖最少，体积最小）"
	ui_print " 20 秒未选择时下载 $_dl_name 版"
	qsc_volume_choice
	case "$?" in
		0) _dl_impl="rust"; _dl_name="Rust" ;;
		1) _dl_impl="c"; _dl_name="C" ;;
		*) ;;
	esac

	ui_print "- 正在下载 $_dl_name 版守护（含 sha256 校验）..."
	if [ ! -f "$MODPATH/bin/qscd_fetch.sh" ]; then
		ui_print "- 缺少下载脚本，已跳过；请在 WebUI 里下载"
		return 0
	fi

	# 独立进程 + 安装期不重启服务；无论成败都不让它影响安装流程
	_dl_out="$(MODDIR="$MODPATH" QSCD_NO_RESTART=1 \
		sh "$MODPATH/bin/qscd_fetch.sh" install "$_dl_impl" 2>/dev/null)"
	if echo "$_dl_out" | grep -q '^ok=1'; then
		ui_print "- 守护已下载并通过自检（$_dl_name 版）"
		return 0
	fi

	_dl_err="$(echo "$_dl_out" | sed -n 's/^error=//p' | head -1)"
	case "$_dl_err" in
		manifest_download_failed | download_failed)
			ui_print "- 下载失败（网络不通或超时）" ;;
		sha256_mismatch) ui_print "- 文件校验不通过，已丢弃" ;;
		no_sha256_tool) ui_print "- 系统缺少 sha256 工具，无法校验，已放弃" ;;
		probe_failed) ui_print "- 本机自检未通过，已回滚" ;;
		unsupported_arch) ui_print "- 本机架构无可用守护文件" ;;
		*) ui_print "- 下载未成功（${_dl_err:-未知原因}）" ;;
	esac
	ui_print "- 不影响安装：请在 WebUI「事件唤醒（守护）」里重试"
	return 0
}
install_qscd

# 可选：安装伴侣 APP（优先模块内嵌 APK；在线下载逻辑保留但已注释）
# APP_UPDATE_JSON="${QSC_APP_UPDATE_URL:-https://eikeitsu.github.io/QSC-Battery/app-update.json}"
#
# qsc_http_get() {
# 	# $1=url $2=dest
# 	_url="$1"
# 	_dest="$2"
# 	if command -v curl >/dev/null 2>&1; then
# 		curl -fsSL --connect-timeout 15 --max-time 180 -o "$_dest" "$_url" 2>/dev/null \
# 			&& [ -s "$_dest" ] && return 0
# 	fi
# 	if command -v wget >/dev/null 2>&1; then
# 		wget -q -O "$_dest" "$_url" 2>/dev/null && [ -s "$_dest" ] && return 0
# 	fi
# 	if command -v busybox >/dev/null 2>&1; then
# 		busybox wget -q -O "$_dest" "$_url" 2>/dev/null && [ -s "$_dest" ] && return 0
# 	fi
# 	return 1
# }

install_companion_app

# 外部 CLI：仅装到 /data/adb/qsc/bin/qsc（不挂 system，避免暴露 Magisk）
install_qsc_cli

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
	[ -d "$MODPATH/install" ] && set_perm_recursive "$MODPATH/install" root root 0755 0644
	[ -d "$MODPATH/assets" ] && set_perm_recursive "$MODPATH/assets" root root 0755 0644
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" root root 0755 0644
set_perm "$MODPATH/service.sh" root root 0755
set_perm "$MODPATH/uninstall.sh" root root 0755
set_perm "$MODPATH/action.sh" root root 0755
set_perm "$MODPATH/customize.sh" root root 0755
set_perm "$MODPATH/hotinstall.sh" root root 0755
[ -f "$MODPATH/bin/qscd" ] && set_perm "$MODPATH/bin/qscd" root root 0755
[ -f "$MODPATH/bin/qscd_fetch.sh" ] && set_perm "$MODPATH/bin/qscd_fetch.sh" root root 0755
[ -f "$MODPATH/bin/qsc_status.sh" ] && set_perm "$MODPATH/bin/qsc_status.sh" root root 0755
[ -f "$MODPATH/bin/qsc" ] && set_perm "$MODPATH/bin/qsc" root root 0755
[ -f /data/adb/qsc/bin/qsc ] && set_perm /data/adb/qsc/bin/qsc root root 0755

# 非首次：本模块无 system/sepolicy 等开机挂载，更新默认可免重启
if [ "$INSTALL_WEBUI" = "1" ] && [ -f "$LIBDIR/hot_update.sh" ]; then
	# shellcheck disable=SC1090
	. "$LIBDIR/hot_update.sh"
	type hot_update_prune_webroot >/dev/null 2>&1 &&
		hot_update_prune_webroot "$MODPATH"
fi

ui_print "--------------------------------"
if [ "$QSC_FORCE_CLEAN_INSTALL" = "1" ]; then
	ui_print " 强制完整重装完成：请重启设备后重新设置"
elif [ -f "$LIBDIR/hot_update.sh" ]; then
	HOT_UPDATE_DESC="[♻️热更新中 | 正在重启服务] 本次更新无需重启；稍后自动显示实时充电状态"
	# 无「必须重启」路径 → 空参数列表；仅首次/禁用时会要求重启
	if hot_update_try QSC_Battery; then
		ui_print " 热更新将重启充电控制服务 "
	fi
else
	ui_print " 安装完成，请重启设备 "
fi
rm -f /data/adb/qsc/install_auto 2>/dev/null
ui_print "********************************"
