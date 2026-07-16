#!/system/bin/sh

# QSC 旧版 -> 新版目录迁移
# 用法: qsc_run_migration [install|boot]
# install 模式通过 ui_print 输出，boot 模式写入 data/migrate.log

qsc_migration_log() {
	local mode="$1"
	local message="$2"
	local log_file="${MODPATH:-$MODDIR}/data/migrate.log"
	mkdir -p "${MODPATH:-$MODDIR}/data"
	echo "$(date +%F_%T) $message" >> "$log_file"
	if [ "$mode" = "install" ]; then
		ui_print "  $message"
	fi
}

qsc_run_migration() {
	local mode="${1:-boot}"
	local migrated=0
	local modroot="${MODPATH:-$MODDIR}"

	[ -z "$modroot" ] && return 1

	MODDIR="$modroot"
	BINDIR="$MODDIR/bin"
	CONFDIR="$MODDIR/config"
	DATADIR="$MODDIR/data"
	ASSETDIR="$MODDIR/assets"
	CONF="$CONFDIR/config.conf"
	OFF_FLAG="$DATADIR/off_qsc"

	mkdir -p "$CONFDIR" "$DATADIR" "$BINDIR" "$ASSETDIR"
	mkdir -p "$MODDIR/webroot"

	qsc_migration_log "$mode" "========================================"
	qsc_migration_log "$mode" "QSC 目录迁移检查开始"

	if [ -f "$MODDIR/config.conf" ]; then
		if [ ! -f "$CONF" ]; then
			mv "$MODDIR/config.conf" "$CONF"
			qsc_migration_log "$mode" "[迁移] config.conf -> config/config.conf"
			migrated=1
		else
			mv "$MODDIR/config.conf" "$CONF.legacy.bak"
			qsc_migration_log "$mode" "[备份] 旧 config.conf -> config/config.conf.legacy.bak"
			migrated=1
		fi
	fi

	for f in log.log startup.log debug.log service_start.log list_switch \
		off_qsc power_on power_off power_switch now_c off_d temp_switch \
		no_battery_logged no_temp_logged no_node_logged .safe_tmp .dumpsys_tmp; do
		if [ -f "$MODDIR/$f" ] && [ ! -e "$DATADIR/$f" ]; then
			mv "$MODDIR/$f" "$DATADIR/$f"
			qsc_migration_log "$mode" "[迁移] $f -> data/$f"
			migrated=1
		fi
	done

	if [ -f "$MODDIR/off_qsc" ] && [ ! -f "$OFF_FLAG" ]; then
		mv "$MODDIR/off_qsc" "$OFF_FLAG"
		qsc_migration_log "$mode" "[迁移] off_qsc -> data/off_qsc"
		migrated=1
	fi

	if [ -f "$MODDIR/pay.jpg" ]; then
		if [ ! -f "$ASSETDIR/pay.jpg" ]; then
			mv "$MODDIR/pay.jpg" "$ASSETDIR/pay.jpg"
			qsc_migration_log "$mode" "[迁移] pay.jpg -> assets/pay.jpg"
		else
			mv "$MODDIR/pay.jpg" "$ASSETDIR/pay.jpg.legacy.bak"
			qsc_migration_log "$mode" "[备份] 旧 pay.jpg -> assets/pay.jpg.legacy.bak"
		fi
		migrated=1
	fi

	if [ -f "$MODDIR/.投币捐赠.jpg" ] && [ ! -f "$ASSETDIR/donate.jpg" ]; then
		mv "$MODDIR/.投币捐赠.jpg" "$ASSETDIR/donate.jpg"
		qsc_migration_log "$mode" "[迁移] .投币捐赠.jpg -> assets/donate.jpg"
		migrated=1
	fi

	for legacy_script in qsc_switch.sh list_switch.sh testing.sh diagnose.sh diag2.sh up upqsc.sh; do
		if [ -f "$MODDIR/$legacy_script" ] && [ -f "$BINDIR/$legacy_script" ]; then
			rm -f "$MODDIR/$legacy_script"
			qsc_migration_log "$mode" "[清理] 移除旧版根目录脚本 $legacy_script"
			migrated=1
		fi
	done

	if [ "$migrated" = "1" ]; then
		qsc_migration_log "$mode" "迁移完成：已从旧版结构升级到新目录"
	else
		qsc_migration_log "$mode" "未检测到需迁移的旧版文件（全新安装或已是最新结构）"
	fi

	qsc_migration_log "$mode" "========================================"
}
