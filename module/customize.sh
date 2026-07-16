#!/system/bin/sh

ui_print "********************************"
ui_print " QSC 定量停充 (WebUI版) "
ui_print " 原作者: top大佬 @酷安 "
ui_print " 维护: 许小墨 @酷安"
ui_print "********************************"

if [ -f "$MODPATH/bin/migrate.sh" ]; then
	. "$MODPATH/bin/migrate.sh"
	ui_print "--------------------------------"
	ui_print " 正在检查旧版模块并迁移数据... "
	if [ -f "$MODPATH/config.conf" ] || [ -f "$MODPATH/qsc_switch.sh" ] || [ -f "$MODPATH/log.log" ]; then
		ui_print " 已检测到旧版目录结构 "
	else
		ui_print " 未检测到旧版残留（可能是全新安装） "
	fi
	qsc_run_migration install
	ui_print "--------------------------------"
else
	ui_print " 警告: migrate.sh 缺失，跳过迁移 "
fi

cp "$MODPATH/module.prop" "$MODPATH/t_module"
mkdir -p "$MODPATH/bin" "$MODPATH/config" "$MODPATH/data" "$MODPATH/webroot"

ui_print "--------------------------------"
ui_print " 目录结构: "
ui_print "  bin/     核心脚本 "
ui_print "  config/  用户配置 "
ui_print "  data/    运行数据 "
ui_print "  webroot/ WebUI 界面 "
ui_print "--------------------------------"
ui_print " 安装后可在 Magisk/KernelSU 打开 WebUI "
ui_print " 配置: config/config.conf "
ui_print " 日志: data/log.log "
ui_print " 迁移日志: data/migrate.log "
ui_print "--------------------------------"
ui_print " 安装完成，请重启设备 "
ui_print "********************************"

set_perm_recursive "$MODPATH/bin" root root 0755 0755
set_perm_recursive "$MODPATH/config" root root 0755 0644
set_perm_recursive "$MODPATH/data" root root 0755 0777
[ -d "$MODPATH/assets" ] && set_perm_recursive "$MODPATH/assets" root root 0755 0644
set_perm_recursive "$MODPATH/webroot" root root 0755 0644
set_perm "$MODPATH/service.sh" root root 0755
set_perm "$MODPATH/uninstall.sh" root root 0755
set_perm "$MODPATH/action.sh" root root 0755
set_perm "$MODPATH/customize.sh" root root 0755

[ -f "$MODPATH/pay.jpg" ] && [ ! -f "$MODPATH/assets/pay.jpg" ] && mv "$MODPATH/pay.jpg" "$MODPATH/assets/pay.jpg"
[ ! -f "$MODPATH/config/config.conf" ] && [ -f "$MODPATH/config.conf" ] && mv "$MODPATH/config.conf" "$MODPATH/config/config.conf"
