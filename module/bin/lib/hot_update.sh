#!/system/bin/sh
# 免重启更新：非首次安装且「需重启路径」无变更时，请求热更新并拉起 hotinstall.sh
# - 管理器提供热更新接口时只 export；否则自行做 modules_update → modules 切换

hot_update_modid() {
	_prop="${1:-$MODPATH/module.prop}"
	if command -v grep_prop >/dev/null 2>&1; then
		grep_prop id "$_prop" 2>/dev/null && return 0
	fi
	sed -n 's/^id=//p' "$_prop" 2>/dev/null | head -n1 | tr -d '\r'
}

# stdout: digest；目录不存在输出 missing
hot_update_tree_digest() {
	_root="$1"
	if [ ! -e "$_root" ]; then
		echo "missing"
		return 0
	fi
	if [ -f "$_root" ]; then
		cksum "$_root" 2>/dev/null | awk '{print $1":"$2}'
		return 0
	fi
	(
		cd "$_root" 2>/dev/null || exit 0
		find . -type f 2>/dev/null | sort | while IFS= read -r _f; do
			[ -n "$_f" ] || continue
			_sum=$(cksum "$_f" 2>/dev/null | awk '{print $1":"$2}')
			echo "$_f $_sum"
		done
	) | cksum | awk '{print $1":"$2}'
}

hot_update_path_changed() {
	_old_root="$1"
	_new_root="$2"
	_rel="$3"
	_o="$_old_root/$_rel"
	_n="$_new_root/$_rel"
	[ "$(hot_update_tree_digest "$_o")" = "$(hot_update_tree_digest "$_n")" ] && return 1
	return 0
}

hot_update_needs_reboot() {
	_old_root="$1"
	_new_root="$2"
	shift 2
	for _rel in "$@"; do
		[ -n "$_rel" ] || continue
		if hot_update_path_changed "$_old_root" "$_new_root" "$_rel"; then
			return 0
		fi
	done
	return 1
}

# 把旧模块中的用户数据并入新包
# 用法: hot_update_preserve_paths <old> <new> rel1 rel2 ...
hot_update_preserve_paths() {
	_old_root="$1"
	_new_root="$2"
	shift 2
	[ -d "$_old_root" ] && [ -d "$_new_root" ] || return 0
	for _rel in "$@"; do
		[ -n "$_rel" ] || continue
		_src="$_old_root/$_rel"
		_dst="$_new_root/$_rel"
		[ -e "$_src" ] || continue
		if [ -d "$_src" ]; then
			mkdir -p "$_dst"
			(
				cd "$_src" 2>/dev/null || exit 0
				find . -type f 2>/dev/null
			) | while IFS= read -r _f; do
				[ -n "$_f" ] || continue
				[ -e "$_dst/$_f" ] && continue
				mkdir -p "$_dst/$(dirname "$_f")"
				cp -f "$_src/$_f" "$_dst/$_f" 2>/dev/null || true
			done
		elif [ -f "$_src" ]; then
			[ -e "$_dst" ] && continue
			mkdir -p "$(dirname "$_dst")"
			cp -f "$_src" "$_dst" 2>/dev/null || true
		fi
	done
}

hot_update_request() {
	_modid="$1"
	_script="${HOT_UPDATE_SCRIPT:-hotinstall.sh}"
	[ -n "$_modid" ] || return 1
	[ -f "$MODPATH/$_script" ] || {
		ui_print "! 缺少 $_script，无法免重启更新"
		return 1
	}

	export MODULE_HOT_INSTALL_REQUEST="true"
	export MODULE_HOT_RUN_SCRIPT="$_script"

	if [ "$MOUNTIFY_HAS_HOT_INSTALL" = "true" ] || [ "$NOMOUNT_HAS_HOT_INSTALL" = "true" ]; then
		ui_print "- 已请求管理器免重启热更新"
		ui_print "- 安装完成后请刷新模块列表，无需重启"
		return 0
	fi

	# Magisk / 普通 KSU·APatch：
	# 禁止「先删旧目录再 mv + 在 modules_update 留 prop 占位」——占位会被管理器二次套用，
	# 把已更新的完整模块盖成只剩 module.prop 的空壳。
	(
		sleep 5
		OLD="/data/adb/modules/$_modid"
		NEW="/data/adb/modules_update/$_modid"
		[ -d "$NEW" ] || exit 0
		[ -d "$OLD" ] || exit 0
		[ -f "$OLD/disable" ] && exit 0
		[ -f "$OLD/remove" ] && exit 0
		[ -f "$NEW/module.prop" ] || exit 0

		# 就地覆盖到现行目录，全程不出现空模块窗口
		cp -a "$NEW"/. "$OLD"/ || exit 1
		# 立刻清掉 update 侧，避免被再次 apply
		rm -rf "$NEW"
		rm -f "$OLD/update" "$OLD/remove" 2>/dev/null

		if [ -f "$OLD/$_script" ]; then
			sh "$OLD/$_script" >/dev/null 2>&1 || true
		fi
	) >/dev/null 2>&1 &

	ui_print "- 已安排免重启热更新（无需重启）"
	ui_print "- 安装完成后请刷新模块列表"
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

	if hot_update_needs_reboot "$_old" "$_new" "$@"; then
		ui_print "- 本次变更含开机挂载/策略类文件：请重启后生效"
		return 1
	fi

	hot_update_request "$_modid"
}
