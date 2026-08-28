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

# 热更新时把安装包里的「等待开机」占位简介换成过渡文案
# 可选环境：HOT_UPDATE_DESC
hot_update_write_desc() {
	_prop="$MODPATH/module.prop"
	[ -n "$HOT_UPDATE_DESC" ] || return 0
	[ -f "$_prop" ] || return 0
	_tmp="$_prop.tmp.$$"
	awk -F= -v desc="$HOT_UPDATE_DESC" '
		BEGIN { done=0 }
		$1 == "description" { print "description=" desc; done=1; next }
		{ print }
		END { if (!done) print "description=" desc }
	' "$_prop" >"$_tmp" && mv -f "$_tmp" "$_prop"
	chmod 0644 "$_prop" 2>/dev/null
}

hot_update_request() {
	_modid="$1"
	_script="${HOT_UPDATE_SCRIPT:-hotinstall.sh}"
	[ -n "$_modid" ] || return 1
	[ -f "$MODPATH/$_script" ] || {
		ui_print "! 缺少 $_script，无法免重启更新"
		return 1
	}

	hot_update_write_desc

	export MODULE_HOT_INSTALL_REQUEST="true"
	export MODULE_HOT_RUN_SCRIPT="$_script"

	if [ "$MOUNTIFY_HAS_HOT_INSTALL" = "true" ] || [ "$NOMOUNT_HAS_HOT_INSTALL" = "true" ]; then
		ui_print "- 已请求管理器免重启热更新"
		ui_print "- 安装完成后请刷新模块列表，无需重启"
		return 0
	fi

	# Magisk / 普通 KSU·APatch：自行把 modules_update 就地覆盖到 modules。
	# 禁止「先删旧目录再 mv + 在 modules_update 留 prop 占位」——占位会被管理器二次套用，
	# 把已更新的完整模块盖成只剩 module.prop 的空壳。
	#
	# 这个作业必须脱离安装器：管理器跑完 customize.sh 后会结束整个会话，
	# 普通 `( ... ) &` 会被连带杀掉，表现就是 modules_update 残留 + modules 下留着 update。
	# 且不能用固定 sleep：管理器在 customize.sh 之后还要改权限、并 touch
	# modules/<id>/update，赛跑赢了也会被它重新写回。
	# 放在两个模块目录之外：worker 要删掉 modules_update，不能跟着被删；
	# 也不能落在 MODPATH 里，否则会被打包进模块目录
	hot_update_spawn_worker "$_modid" "$_script" || return 1

	ui_print "- 已安排免重启热更新（无需重启）"
	ui_print "- 服务会立即重启；模块列表残留标记会在后台清理"
	return 0
}

# 生成收尾作业脚本。参数: 目标路径
# 独立成函数是为了让常驻服务也能用同一份逻辑做兜底：有些第三方安装器
# （如 InstallX）会连带杀掉我们脱离出去的后台作业，那时就由服务重新拉起它。
hot_update_write_worker() {
	_worker_path="$1"
	[ -n "$_worker_path" ] || return 1
	cat >"$_worker_path" <<'HOT_UPDATE_WORKER'
#!/system/bin/sh
# 由 customize.sh 生成并脱离安装器运行；参数: <modid> <hotinstall 脚本名>
MODID="$1"
SCRIPT="$2"
OLD="/data/adb/modules/$MODID"
NEW="/data/adb/modules_update/$MODID"
LOG="$OLD/data/hot_update.log"
LOCK="/data/adb/.${MODID}.hot_update.lock"

if ! mkdir "$LOCK" 2>/dev/null; then
	exit 0
fi
hu_cleanup_lock() {
	rm -rf "$LOCK" 2>/dev/null
}
trap hu_cleanup_lock 0 1 2 15

hu_log() {
	mkdir -p "$OLD/data" 2>/dev/null
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG" 2>/dev/null
}

# 暂存目录的轻量指纹：文件数 + 占用大小
hu_sig() {
	_n="$(find "$NEW" -type f 2>/dev/null | wc -l | tr -d ' ')"
	_k="$(du -sk "$NEW" 2>/dev/null | awk '{print $1}')"
	echo "${_n:-0}:${_k:-0}"
}

# 等管理器写完：指纹连续 3 次（约 3s）不变即认为收尾结束
hu_wait_stable() {
	_prev=""
	_same=0
	_i=0
	while [ "$_i" -lt 60 ]; do
		sleep 1
		_i=$((_i + 1))
		[ -d "$NEW" ] || continue
		_cur="$(hu_sig)"
		if [ "$_cur" = "$_prev" ]; then
			_same=$((_same + 1))
			[ "$_same" -ge 3 ] && return 0
		else
			_same=0
		fi
		_prev="$_cur"
	done
	return 1
}

[ -n "$MODID" ] || exit 0
hu_log "start: 收尾作业已启动 (pid $$)"
if ! hu_wait_stable; then
	hu_log "abort: modules_update 未在 60s 内稳定"
	exit 0
fi

[ -d "$NEW" ] || { hu_log "abort: 无 $NEW"; exit 0; }
[ -d "$OLD" ] || { hu_log "abort: 无 $OLD"; exit 0; }
[ -f "$OLD/disable" ] && { hu_log "abort: 模块已禁用"; exit 0; }
[ -f "$OLD/remove" ] && { hu_log "abort: 模块待卸载"; exit 0; }
# 关键文件齐全才敢覆盖：暂存被中断时不能拿半个包盖掉正在用的模块
for f in module.prop service.sh bin/common.sh; do
	[ -f "$NEW/$f" ] || { hu_log "abort: 暂存缺少 $f"; exit 0; }
done

# 就地覆盖（只增改不删），全程不出现空模块窗口
if ! cp -a "$NEW"/. "$OLD"/ 2>/dev/null; then
	hu_log "fail: 覆盖 $OLD 失败，将按重启生效"
	exit 1
fi
hu_log "ok: 已就地覆盖到 $OLD"

# 生效与清理分离：复制成功后立刻清除当前更新标记并执行 hotinstall，
# 不再让第三方安装器的延迟收尾阻塞服务重启。
rm -rf "$NEW" 2>/dev/null
rm -f "$OLD/update" "$OLD/remove" 2>/dev/null
if [ -f "$OLD/$SCRIPT" ]; then
	sh "$OLD/$SCRIPT" >/dev/null 2>&1 &
	hu_log "ok: 已启动 $SCRIPT（立即生效，pid $!）"
fi

# 管理器可能在我们之后才 touch update / 回写暂存，持续清理一段时间。
# 窗口给足 120 秒：第三方安装器（InstallX 等）收尾比管理器慢得多，
# 原先 20 秒经常是我们先退场、它后 touch update，用户就又看到「需重启」。
# 暂存只在前几秒清：再往后出现的暂存更可能是用户又刷了一次包，不能删。
_i=0
_seen_update=0
while [ "$_i" -lt 120 ]; do
	[ "$_i" -lt 5 ] && rm -rf "$NEW" 2>/dev/null
	[ -f "$OLD/update" ] && _seen_update=$((_seen_update + 1))
	rm -f "$OLD/update" "$OLD/remove" 2>/dev/null
	sleep 1
	_i=$((_i + 1))
done
[ "$_seen_update" -gt 0 ] && hu_log "info: 期间清理 update 标记 ${_seen_update} 次"
[ -e "$NEW" ] && hu_log "warn: $NEW 仍残留"
[ -f "$OLD/update" ] && hu_log "warn: $OLD/update 仍残留"
rm -f /data/adb/.qsc_hot_update.sh 2>/dev/null
HOT_UPDATE_WORKER
	chmod 0700 "$_worker_path" 2>/dev/null
}

# 写出并脱离当前会话启动收尾作业。参数: <modid> <hotinstall 脚本名>
hot_update_spawn_worker() {
	_sw_modid="$1"
	_sw_script="${2:-hotinstall.sh}"
	[ -n "$_sw_modid" ] || return 1
	# 放在两个模块目录之外：worker 要删掉 modules_update，不能跟着被删；
	# 也不能落在 MODPATH 里，否则会被打包进模块目录
	_sw_path="/data/adb/.qsc_hot_update.sh"
	hot_update_write_worker "$_sw_path" || return 1
	# setsid 才能真正脱离安装器的会话；没有就退回 nohup
	if command -v setsid >/dev/null 2>&1; then
		setsid sh "$_sw_path" "$_sw_modid" "$_sw_script" </dev/null >/dev/null 2>&1 &
	else
		nohup sh "$_sw_path" "$_sw_modid" "$_sw_script" </dev/null >/dev/null 2>&1 &
	fi
	return 0
}

hot_update_versioncode() {
	sed -n 's/^versionCode=//p' "$1" 2>/dev/null | head -n1 | tr -d ' \r'
}

# 运行期兜底：安装器把我们脱离出去的收尾作业杀掉时，由常驻服务自己了结。
# InstallX 这类第三方安装器就会这样，表现是 modules_update 残留 +
# 模块目录留着 update，管理器一直提示需重启。
#
# 只看两样东西：模块目录里的 update 标记，和 modules_update 里的暂存。
#   暂存版本更高 → 安装器没能应用，重新拉起收尾作业（它在模块目录之外跑，
#                  不会出现「覆盖正在执行的 service.sh」这种自伤）
#   暂存同版本或没有暂存 → 标记是残留，删掉，免得白提示重启
# 真正待应用的更新一定会提高 versionCode，所以这个判据不会把更新弄丢。
# 返回 0 = 做了处理
qsc_hot_finalize() {
	local modid new mine theirs f
	[ -f "$MODDIR/update" ] || return 1
	modid="$(sed -n 's/^id=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1 | tr -d ' \r')"
	[ -n "$modid" ] || return 1
	new="/data/adb/modules_update/$modid"
	mine="$(hot_update_versioncode "$MODDIR/module.prop")"
	case "$mine" in "" | *[!0-9]*) return 1 ;; esac
	theirs=""
	[ -f "$new/module.prop" ] && theirs="$(hot_update_versioncode "$new/module.prop")"
	case "$theirs" in *[!0-9]*) theirs="" ;; esac

	if [ -n "$theirs" ] && [ "$theirs" -gt "$mine" ] 2>/dev/null; then
		for f in module.prop service.sh bin/common.sh; do
			if [ ! -f "$new/$f" ]; then
				qsc_log_once hot_fin warn "暂存的更新缺少 $f，改为重启生效"
				return 1
			fi
		done
		if hot_update_spawn_worker "$modid" hotinstall.sh; then
			qsc_log info "检测到未完成的免重启更新（暂存 $theirs > 当前 $mine），已重新拉起收尾作业"
			return 0
		fi
		return 1
	fi

	rm -f "$MODDIR/update" 2>/dev/null
	if [ -n "$theirs" ] && [ "$theirs" = "$mine" ]; then
		rm -rf "$new" 2>/dev/null
	fi
	qsc_log info "已清理残留的重启标记（暂存版本 ${theirs:-无}，当前 $mine）"
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
