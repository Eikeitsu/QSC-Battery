#!/system/bin/sh
# hot_update: finalize / verify
qsc_hot_finalize() {
	local modid new payload source mine theirs f
	[ -f "$MODDIR/update" ] ||
		[ -d "/data/adb/qsc/hot_update/payload/QSC_Battery" ] ||
		return 1
	modid="$(sed -n 's/^id=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1 | tr -d ' \r')"
	[ -n "$modid" ] || return 1
	new="/data/adb/modules_update/$modid"
	payload="/data/adb/qsc/hot_update/payload/$modid"
	mine="$(hot_update_versioncode "$MODDIR/module.prop")"
	case "$mine" in "" | *[!0-9]*) return 1 ;; esac
	theirs=""
	source="$payload"
	[ -f "$new/module.prop" ] && source="$new"
	[ -f "$source/module.prop" ] && theirs="$(hot_update_versioncode "$source/module.prop")"
	case "$theirs" in *[!0-9]*) theirs="" ;; esac

	if [ -n "$theirs" ] && [ "$theirs" -gt "$mine" ] 2>/dev/null; then
		for f in module.prop service.sh bin/common.sh hotinstall.sh; do
			if [ ! -f "$source/$f" ]; then
				qsc_log_once hot_fin warn "更新源缺少 $f，保留标准更新流程"
				return 1
			fi
		done
		if hot_update_spawn_worker "$modid" hotinstall.sh "$source"; then
			qsc_log info "检测到未完成的免重启更新（更新源 $theirs > 当前 $mine），已重新拉起收尾作业"
			return 0
		fi
		return 1
	fi

	# worker 可能恰好在复制完成后被杀掉：当前版本已更新，但清理还没执行。
	# 只有关键文件与完整更新源逐一一致时，才允许完成清理。
	if [ -n "$theirs" ] && [ "$theirs" = "$mine" ]; then
		for f in module.prop service.sh bin/common.sh hotinstall.sh; do
			if [ ! -f "$source/$f" ] || hot_update_path_changed "$MODDIR" "$source" "$f"; then
				qsc_log_once hot_fin_verify warn "当前模块与同版本更新源不一致，保留标准更新流程"
				return 1
			fi
		done
		if [ "$source" = "$new" ] && [ -e "$new" ]; then
			rm -rf "$new" 2>/dev/null || return 1
			[ ! -e "$new" ] || return 1
		fi
		if [ -f "$MODDIR/update" ]; then
			rm -f "$MODDIR/update" 2>/dev/null || return 1
			[ ! -e "$MODDIR/update" ] || return 1
		fi
		if [ "$source" = "$payload" ]; then
			rm -rf "$payload" 2>/dev/null
			rmdir /data/adb/qsc/hot_update/payload 2>/dev/null
		fi
		rm -f /data/adb/qsc/hot_update/worker.sh 2>/dev/null
		rmdir /data/adb/qsc/hot_update/transactions 2>/dev/null
		rmdir /data/adb/qsc/hot_update 2>/dev/null
		qsc_log info "已确认热更新完成并清理残留标记（版本 $mine）"
		return 0
	fi

	qsc_log_once hot_fin_pending debug \
		"未确认热更新完成：更新源版本=${theirs:-无} 当前=$mine，保留标准更新标记"
	return 1
}

# 返回: 0=已请求热更；1=需重启 / 首次安装
hot_update_try() {
	_modid="$1"
	shift
	_old="/data/adb/modules/$_modid"
	_new="${MODPATH:-}"

	if [ -z "$_new" ] || [ ! -d "$_new" ]; then
		return 1
	fi

	if [ ! -d "$_old" ] || [ -f "$_old/remove" ]; then
		ui_print "- 首次安装：请重启后生效"
		return 1
	fi

	if [ -f "$_old/disable" ]; then
		ui_print "- 模块当前为禁用状态：请重启（或启用后）再生效"
		return 1
	fi

	_old_version="$(hot_update_versioncode "$_old/module.prop")"
	_new_version="$(hot_update_versioncode "$_new/module.prop")"
	case "$_old_version:$_new_version" in
		*[!0-9:]*|*:|:*)
			ui_print "- 模块版本号无效：保留标准重启更新"
			return 1
			;;
	esac
	if [ "$_new_version" -le "$_old_version" ] 2>/dev/null; then
		ui_print "- 目标版本未高于当前版本：保留标准重启更新"
		return 1
	fi

	if hot_update_needs_reboot "$_old" "$_new" "$@"; then
		ui_print "- 本次变更含开机挂载/策略类文件：请重启后生效"
		return 1
	fi

	hot_update_request "$_modid"
}
