#!/system/bin/sh
# hot_update: finalize / verify
# 管理器只在开机早期把 modules_update 换进 modules。服务若已跑起来而 update
# 还在，说明这次替换没发生；继续留着标记只会让模块开关一直不可点。
qsc_hot_clear_stuck_markers() {
	local reason="$1" level="${2:-warn}"
	rm -f "$MODDIR/update" "$MODDIR/remove" \
		"$DATADIR/hot_update_fallback_reboot" \
		"$DATADIR/hot_update_at" \
		"$DATADIR/hot_update_fin_tries" 2>/dev/null
	rm -rf "/data/adb/qsc/hot_update/transactions/QSC_Battery" \
		"/data/adb/qsc/hot_update/payload/QSC_Battery" 2>/dev/null
	rm -f /data/adb/qsc/hot_update/worker.sh \
		/data/adb/qsc/hot_update/verify.sh 2>/dev/null
	rmdir /data/adb/qsc/hot_update/payload \
		/data/adb/qsc/hot_update/transactions \
		/data/adb/qsc/hot_update 2>/dev/null
	if [ "$level" = "info" ]; then
		qsc_log info "$reason"
	else
		qsc_log warn "已清除无法完成的更新标记：${reason}"
	fi
}

qsc_hot_spawn_bounded() {
	local modid="$1" source="$2" note="$3" tries
	tries="$(cat "$DATADIR/hot_update_fin_tries" 2>/dev/null | tr -d ' \r\n')"
	case "$tries" in ""|*[!0-9]*) tries=0 ;; esac
	if [ "$tries" -ge 3 ] 2>/dev/null; then
		qsc_hot_clear_stuck_markers "已重试 ${tries} 次仍未完成（${note}）"
		return 0
	fi
	printf '%s\n' "$((tries + 1))" >"$DATADIR/hot_update_fin_tries" 2>/dev/null
	if hot_update_spawn_worker "$modid" hotinstall.sh "$source"; then
		qsc_log info "重新拉起热更新（${note}，第 $((tries + 1)) 次）"
		return 0
	fi
	qsc_hot_clear_stuck_markers "无法重新拉起热更新（${note}）"
	return 0
}

qsc_hot_finalize() {
	local modid new payload source mine theirs f mismatch
	[ -f "$MODDIR/update" ] ||
		[ -d "/data/adb/qsc/hot_update/payload/QSC_Battery" ] ||
		[ -f "/data/adb/qsc/hot_update/transactions/QSC_Battery/state" ] ||
		[ -f "$DATADIR/hot_update_fallback_reboot" ] ||
		return 1
	modid="$(sed -n 's/^id=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1 | tr -d ' \r')"
	[ -n "$modid" ] || return 1
	new="/data/adb/modules_update/$modid"
	payload="/data/adb/qsc/hot_update/payload/$modid"
	mine="$(hot_update_versioncode "$MODDIR/module.prop")"
	case "$mine" in "" | *[!0-9]*) return 1 ;; esac
	theirs=""
	source=""
	if [ -f "$new/module.prop" ]; then
		source="$new"
	elif [ -f "$payload/module.prop" ]; then
		source="$payload"
	fi
	[ -n "$source" ] && theirs="$(hot_update_versioncode "$source/module.prop")"
	case "$theirs" in *[!0-9]*) theirs="" ;; esac

	if [ -n "$theirs" ] && [ "$theirs" -gt "$mine" ] 2>/dev/null; then
		for f in module.prop service.sh bin/common.sh hotinstall.sh; do
			if [ ! -f "$source/$f" ]; then
				qsc_hot_clear_stuck_markers "更新源缺少 $f"
				return 0
			fi
		done
		qsc_hot_spawn_bounded "$modid" "$source" "更新源 $theirs > 当前 $mine"
		return 0
	fi

	# 热复制已经把新文件盖进正在运行的目录时，版本相同。
	# 管理器若没在开机时替换目录，不能再把 update 留着。
	if [ -n "$theirs" ] && [ "$theirs" = "$mine" ]; then
		mismatch=0
		# module.prop 的 description 会被服务改掉，不能拿整文件摘要比较
		for f in service.sh bin/common.sh hotinstall.sh; do
			if [ ! -f "$MODDIR/$f" ] || [ ! -f "$source/$f" ] ||
				hot_update_path_changed "$MODDIR" "$source" "$f"; then
				mismatch=1
				break
			fi
		done
		if [ "$mismatch" = 1 ]; then
			qsc_hot_spawn_bounded "$modid" "$source" "同版本但关键文件不一致"
			return 0
		fi
		if [ "$source" = "$new" ] && [ -e "$new" ]; then
			rm -rf "$new" 2>/dev/null || {
				qsc_hot_clear_stuck_markers "无法删除 modules_update"
				return 0
			}
			if [ -e "$new" ]; then
				qsc_hot_clear_stuck_markers "modules_update 删除后仍在"
				return 0
			fi
		fi
		qsc_hot_clear_stuck_markers "已确认更新完成并清理残留标记（版本 $mine）" info
		return 0
	fi

	if [ -d "$new" ] && [ ! -f "$new/module.prop" ]; then
		rm -rf "$new" 2>/dev/null || true
	fi
	qsc_hot_clear_stuck_markers "更新源版本=${theirs:-无} 当前=$mine，开机未能替换模块"
	return 0
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
