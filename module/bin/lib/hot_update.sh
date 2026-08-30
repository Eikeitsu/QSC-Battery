#!/system/bin/sh
# 免重启更新：非首次安装且「需重启路径」无变更时，请求热更新并拉起 hotinstall.sh
# - 管理器提供热更新接口时只 export；否则自行做 modules_update → modules 切换

QSC_ADB_DIR="/data/adb/qsc"
QSC_HOT_UPDATE_DIR="$QSC_ADB_DIR/hot_update"
QSC_HOT_PAYLOAD_DIR="$QSC_HOT_UPDATE_DIR/payload"
QSC_HOT_TXN_DIR="$QSC_HOT_UPDATE_DIR/transactions"
QSC_HOT_VERIFY_SCRIPT="$QSC_HOT_UPDATE_DIR/verify.sh"
QSC_HOT_WORKER_SCRIPT="$QSC_HOT_UPDATE_DIR/worker.sh"
QSC_HOT_LOCK_DIR="$QSC_HOT_UPDATE_DIR/lock"

hot_update_migrate_legacy_paths() {
	# 旧版本把热更新临时资源散落在 /data/adb 根目录。先终止旧收尾脚本，
	# 再整体迁移，避免新旧 worker 同时操作两套状态。
	if command -v pkill >/dev/null 2>&1; then
		pkill -f '/data/adb/.qsc_hot_update.sh' 2>/dev/null || true
		pkill -f '/data/adb/.qsc_hot_update_verify.sh' 2>/dev/null || true
	fi
	mkdir -p "$QSC_HOT_UPDATE_DIR" 2>/dev/null || return 1
	if [ -d "/data/adb/.qsc_hot_update_payload" ] &&
		[ ! -e "$QSC_HOT_PAYLOAD_DIR" ]; then
		mv -f /data/adb/.qsc_hot_update_payload "$QSC_HOT_PAYLOAD_DIR" 2>/dev/null || true
	fi
	if [ -d "/data/adb/.qsc_hot_update_txn" ] &&
		[ ! -e "$QSC_HOT_TXN_DIR" ]; then
		mv -f /data/adb/.qsc_hot_update_txn "$QSC_HOT_TXN_DIR" 2>/dev/null || true
	fi
	if [ -f "/data/adb/.qsc_hot_update_verify.sh" ] &&
		[ ! -e "$QSC_HOT_VERIFY_SCRIPT" ]; then
		mv -f /data/adb/.qsc_hot_update_verify.sh "$QSC_HOT_VERIFY_SCRIPT" 2>/dev/null || true
	fi
	if [ -f "/data/adb/.qsc_hot_update.sh" ] &&
		[ ! -e "$QSC_HOT_WORKER_SCRIPT" ]; then
		mv -f /data/adb/.qsc_hot_update.sh "$QSC_HOT_WORKER_SCRIPT" 2>/dev/null || true
	fi
	if [ -d "/data/adb/.QSC_Battery.hot_update.lock" ] &&
		[ ! -e "$QSC_HOT_LOCK_DIR" ]; then
		mv -f /data/adb/.QSC_Battery.hot_update.lock "$QSC_HOT_LOCK_DIR" 2>/dev/null || true
	fi
	rm -rf /data/adb/.qsc_hot_update_payload \
		/data/adb/.qsc_hot_update_txn \
		/data/adb/.qsc_hot_update_verify.sh \
		/data/adb/.qsc_hot_update.sh \
		/data/adb/.QSC_Battery.hot_update.lock 2>/dev/null
	rmdir /data/adb/qsc 2>/dev/null
}

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
	type qsc_description_lock_acquire >/dev/null 2>&1 &&
		qsc_description_lock_acquire || return 1
	_tmp="$_prop.tmp.$$"
	awk -F= -v desc="$HOT_UPDATE_DESC" '
		BEGIN { done=0 }
		$1 == "description" { print "description=" desc; done=1; next }
		{ print }
		END { if (!done) print "description=" desc }
	' "$_prop" >"$_tmp" && mv -f "$_tmp" "$_prop"
	_rc="$?"
	if [ "$_rc" -eq 0 ]; then
		chmod 0644 "$_prop" 2>/dev/null || _rc="$?"
	fi
	[ "$_rc" -eq 0 ] || rm -f "$_tmp" 2>/dev/null
	type qsc_description_lock_release >/dev/null 2>&1 &&
		qsc_description_lock_release
	return "$_rc"
}

hot_update_transaction_write() {
	_txn_modid="$1"
	_txn_state="$2"
	_txn_source_version="$3"
	_txn_target_version="$4"
	_txn_payload="${5:-}"
	_txn_base="$QSC_HOT_TXN_DIR"
	_txn_dir="$_txn_base/$_txn_modid"
	_txn_now="$(date +%s 2>/dev/null)"
	case "$_txn_now" in ""|*[!0-9]*) _txn_now=0 ;; esac
	[ -n "$_txn_modid" ] && [ -n "$_txn_state" ] || return 1
	mkdir -p "$_txn_base" "$_txn_dir" 2>/dev/null || return 1
	_txn_id="$_txn_modid.$_txn_now.$$"
	{
		printf 'id=%s\n' "$_txn_id"
		printf 'state=%s\n' "$_txn_state"
		printf 'source_version=%s\n' "$_txn_source_version"
		printf 'target_version=%s\n' "$_txn_target_version"
		printf 'payload=%s\n' "$_txn_payload"
		printf 'updated_at=%s\n' "$_txn_now"
	} >"$_txn_dir/state.tmp.$$" 2>/dev/null &&
		mv -f "$_txn_dir/state.tmp.$$" "$_txn_dir/state" 2>/dev/null
}

# 把完整的新模块先保存到管理器不会清理的目录。
# 这样即使安装器随后删除 modules_update，也不会丢失待热切换的内容。
hot_update_snapshot_payload() {
	_snapshot_src="$1"
	_snapshot_id="$2"
	_snapshot_base="$QSC_HOT_PAYLOAD_DIR"
	_snapshot_tmp="$_snapshot_base/.${_snapshot_id}.tmp.$$"
	_snapshot_dst="$_snapshot_base/$_snapshot_id"
	HOT_UPDATE_PAYLOAD=""
	[ -d "$_snapshot_src" ] || return 1
	mkdir -p "$_snapshot_base" 2>/dev/null || return 1
	rm -rf "$_snapshot_tmp" 2>/dev/null
	mkdir -p "$_snapshot_tmp" 2>/dev/null || return 1
	_snapshot_err="$(cp -rfp "$_snapshot_src"/. "$_snapshot_tmp"/ 2>&1)"
	_snapshot_rc=$?
	if [ "$_snapshot_rc" -ne 0 ]; then
		rm -rf "$_snapshot_tmp" 2>/dev/null
		ui_print "! 无法保存热更新副本 rc=$_snapshot_rc ${_snapshot_err:-无输出}"
		return 1
	fi
	for _snapshot_file in module.prop service.sh bin/common.sh hotinstall.sh; do
		if [ ! -f "$_snapshot_tmp/$_snapshot_file" ]; then
			rm -rf "$_snapshot_tmp" 2>/dev/null
			ui_print "! 热更新副本缺少 $_snapshot_file，保留标准重启更新"
			return 1
		fi
		_snapshot_sum="$(cksum "$_snapshot_tmp/$_snapshot_file" 2>/dev/null | awk '{print $1":"$2}')"
		if [ -z "$_snapshot_sum" ]; then
			rm -rf "$_snapshot_tmp" 2>/dev/null
			ui_print "! 热更新副本校验失败，保留标准重启更新"
			return 1
		fi
	done
	rm -rf "$_snapshot_dst" 2>/dev/null
	if ! mv -f "$_snapshot_tmp" "$_snapshot_dst" 2>/dev/null; then
		rm -rf "$_snapshot_tmp" 2>/dev/null
		ui_print "! 无法提交热更新副本，保留标准重启更新"
		return 1
	fi
	HOT_UPDATE_PAYLOAD="$_snapshot_dst"
	return 0
}

hot_update_start_verifier() {
	_verify_old="$1"
	_verify_modid="${2:-QSC_Battery}"
	_verify_new="/data/adb/modules_update/$_verify_modid"
	_verify_txn="$QSC_HOT_TXN_DIR/$_verify_modid/state"
	_verify_path="$QSC_HOT_VERIFY_SCRIPT"
	[ -d "$_verify_old" ] && [ -f "$_verify_txn" ] || return 0
	cat >"$_verify_path" <<'HOT_UPDATE_VERIFY'
#!/system/bin/sh
MODID="$1"
OLD="$2"
NEW="$3"
TXN="$4"
SELF="$0"
LOG="$OLD/data/hot_update.log"
PAYLOAD="$(sed -n 's/^payload=//p' "$TXN" 2>/dev/null | head -n1)"
hu_log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG" 2>/dev/null
}
hu_txn_state() {
	_state="$1"
	[ -f "$TXN" ] || return 1
	sed -i "s/^state=.*/state=$_state/" "$TXN" 2>/dev/null
}
hu_fallback() {
	hu_txn_state fallback
	touch "$OLD/data/hot_update_fallback_reboot" "$OLD/update" 2>/dev/null
	if [ ! -d "$NEW" ] && [ -d "$PAYLOAD" ]; then
		mkdir -p "$NEW" 2>/dev/null
		cp -rfp "$PAYLOAD"/. "$NEW"/ 2>/dev/null || true
	fi
	if [ -f "$OLD/bin/common.sh" ]; then
		MODDIR="$OLD"
		. "$OLD/bin/common.sh" 2>/dev/null || true
		type qsc_write_module_description >/dev/null 2>&1 &&
			qsc_write_module_description "⚠️热更新未完成" "请重启设备完成更新" \
				"服务接管校验失败，已保留标准更新流程"
	fi
	hu_log "fallback: verifier 未确认 service 接管，保留标准重启更新"
	rm -f "$SELF" /data/adb/qsc/hot_update/worker.sh 2>/dev/null
}
TARGET_VERSION="$(sed -n 's/^target_version=//p' "$TXN" 2>/dev/null | head -n1 | tr -d ' \r')"
CURRENT_VERSION="$(sed -n 's/^versionCode=//p' "$OLD/module.prop" 2>/dev/null | head -n1 | tr -d ' \r')"
case "$TARGET_VERSION:$CURRENT_VERSION" in
	*[!0-9:]*|*:|:*)
		hu_fallback
		exit 1
		;;
esac
[ "$TARGET_VERSION" = "$CURRENT_VERSION" ] || {
	hu_fallback
	exit 1
}
_i=0
_verified=0
while [ "$_i" -lt 40 ]; do
	_pid="$(cat "$OLD/data/service_pid" 2>/dev/null | tr -d ' \r\n')"
	_hb="$(cat "$OLD/data/service_heartbeat" 2>/dev/null | tr -d ' \r\n')"
	_loops="$(cat "$OLD/data/service_loop_count" 2>/dev/null | tr -d ' \r\n')"
	_worker_pid="$(cat "$OLD/data/description_worker.pid" 2>/dev/null | tr -d ' \r\n')"
	_worker_refresh="$(sed -n 's/^last_refresh=//p' "$OLD/data/description_worker.state" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	case "$_pid:$_hb:$_loops:$_worker_pid:$_worker_refresh" in
		*[!0-9:]*) ;;
		*)
			if kill -0 "$_pid" 2>/dev/null &&
				[ "$_loops" -gt 0 ] 2>/dev/null &&
				kill -0 "$_worker_pid" 2>/dev/null; then
				_now="$(date +%s 2>/dev/null)"
				[ "$_now" -ge "$_hb" ] 2>/dev/null &&
					[ "$((_now - _hb))" -le 10 ] 2>/dev/null &&
					[ "$_now" -ge "$_worker_refresh" ] 2>/dev/null &&
					[ "$((_now - _worker_refresh))" -le 40 ] 2>/dev/null &&
					_verified=1
			fi
			;;
	esac
	[ "$_verified" -eq 1 ] && break
	sleep 1
	_i=$((_i + 1))
done
if [ "$_verified" -ne 1 ]; then
	hu_fallback
	exit 1
fi
hu_txn_state commit || {
	hu_fallback
	exit 1
}
rm -rf "$NEW" 2>/dev/null
if [ -e "$NEW" ]; then
	hu_fallback
	exit 1
fi
rm -f "$OLD/update" "$OLD/remove" 2>/dev/null
[ ! -e "$OLD/update" ] || {
	hu_fallback
	exit 1
}
rm -rf /data/adb/qsc/hot_update/payload/"$MODID" 2>/dev/null
rmdir /data/adb/qsc/hot_update/payload 2>/dev/null
rmdir /data/adb/qsc/hot_update 2>/dev/null
rm -f /data/adb/qsc/hot_update/worker.sh 2>/dev/null
rm -rf "$(dirname "$TXN")" 2>/dev/null
rm -f "$SELF" /data/adb/qsc/hot_update/worker.sh 2>/dev/null
hu_log "commit: verifier 确认 service 心跳、主循环和简介 worker 均正常"
HOT_UPDATE_VERIFY
	chmod 0700 "$_verify_path" 2>/dev/null || return 1
	if command -v setsid >/dev/null 2>&1; then
		setsid sh "$_verify_path" "$_verify_modid" "$_verify_old" \
			"$_verify_new" "$_verify_txn" </dev/null >/dev/null 2>&1 &
	else
		nohup sh "$_verify_path" "$_verify_modid" "$_verify_old" \
			"$_verify_new" "$_verify_txn" </dev/null >/dev/null 2>&1 &
	fi
}

hot_update_request() {
	_modid="$1"
	_script="${HOT_UPDATE_SCRIPT:-hotinstall.sh}"
	_old="/data/adb/modules/$_modid"
	_source_version="$(hot_update_versioncode "$_old/module.prop")"
	_target_version="$(hot_update_versioncode "$MODPATH/module.prop")"
	[ -n "$_modid" ] || return 1
	[ -f "$MODPATH/$_script" ] || {
		ui_print "! 缺少 $_script，无法免重启更新"
		return 1
	}

	hot_update_write_desc

	export MODULE_HOT_INSTALL_REQUEST="true"
	export MODULE_HOT_RUN_SCRIPT="$_script"

	if [ "$MOUNTIFY_HAS_HOT_INSTALL" = "true" ] || [ "$NOMOUNT_HAS_HOT_INSTALL" = "true" ]; then
		if ! hot_update_snapshot_payload "$MODPATH" "$_modid"; then
			ui_print "- 无法保存热更新副本，保留标准重启更新"
			return 1
		fi
		hot_update_transaction_write "$_modid" prepare \
			"$_source_version" "$_target_version" \
			"$HOT_UPDATE_PAYLOAD" || {
			rm -rf "$HOT_UPDATE_PAYLOAD" 2>/dev/null
			ui_print "- 无法记录热更新事务，保留标准重启更新"
			return 1
		}
		ui_print "- 已请求管理器免重启热更新"
		ui_print "- 安装完成后请刷新模块列表，无需重启"
		return 0
	fi

	# Magisk / 普通 KSU·APatch：保留标准更新目录，同时把完整包复制到
	# 管理器目录之外。worker 优先使用这个副本，避免安装器清理
	# modules_update 后没有可用更新源。
	#
	# 这个作业必须脱离安装器：管理器跑完 customize.sh 后会结束整个会话，
	# 普通 `( ... ) &` 会被连带杀掉，表现就是 modules_update 残留 + modules 下留着 update。
	# 副本准备或热切换失败时不碰 update/modules_update，交给重启流程兜底。
	if ! hot_update_snapshot_payload "$MODPATH" "$_modid"; then
		ui_print "- 热更新副本创建失败：保留标准更新流程，请重启后生效"
		return 1
	fi
	hot_update_transaction_write "$_modid" prepare \
		"$_source_version" "$_target_version" "$HOT_UPDATE_PAYLOAD" || {
		rm -rf "$HOT_UPDATE_PAYLOAD" 2>/dev/null
		ui_print "- 无法记录热更新事务，保留标准重启更新"
		return 1
	}
	hot_update_spawn_worker "$_modid" "$_script" "$HOT_UPDATE_PAYLOAD" || {
		hot_update_transaction_write "$_modid" fallback \
			"$_source_version" "$_target_version" "$HOT_UPDATE_PAYLOAD" || true
		touch "$_old/data/hot_update_fallback_reboot" 2>/dev/null
		ui_print "- 热更新任务启动失败：保留标准更新流程，请重启后生效"
		return 1
	}

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
# 由 customize.sh 生成并脱离安装器运行；参数: <modid> <hotinstall 脚本名> [副本路径]
MODID="$1"
SCRIPT="$2"
PAYLOAD="${3:-/data/adb/qsc/hot_update/payload/$MODID}"
OLD="/data/adb/modules/$MODID"
NEW="/data/adb/modules_update/$MODID"
LOG="$OLD/data/hot_update.log"
LOCK="/data/adb/qsc/hot_update/lock"
TXN_DIR="/data/adb/qsc/hot_update/transactions/$MODID"
TXN_STATE="$TXN_DIR/state"

if ! mkdir "$LOCK" 2>/dev/null; then
	exit 0
fi
echo "$$" >"$LOCK/pid" 2>/dev/null
hu_cleanup_lock() {
	rm -rf "$LOCK" 2>/dev/null
}
trap hu_cleanup_lock 0 1 2 15

hu_log() {
	mkdir -p "$OLD/data" 2>/dev/null
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG" 2>/dev/null
}

hu_txn_set() {
	_state="$1"
	_now="$(date +%s 2>/dev/null)"
	_txn_id="$(sed -n 's/^id=//p' "$TXN_STATE" 2>/dev/null | head -n1 | tr -d ' \r')"
	case "$_now" in ""|*[!0-9]*) _now=0 ;; esac
	mkdir -p "$TXN_DIR" 2>/dev/null || return 1
	[ -n "$_txn_id" ] || _txn_id="$MODID.$_now.$$"
	{
		printf 'id=%s\n' "$_txn_id"
		printf 'state=%s\n' "$_state"
		printf 'source_version=%s\n' "${SOURCE_VERSION:-}"
		printf 'target_version=%s\n' "${RUN_VERSION:-}"
		printf 'payload=%s\n' "$PAYLOAD"
		printf 'updated_at=%s\n' "$_now"
	} >"$TXN_STATE.tmp.$$" 2>/dev/null &&
		mv -f "$TXN_STATE.tmp.$$" "$TXN_STATE" 2>/dev/null
}

hu_fallback() {
	hu_txn_set fallback
	touch "$OLD/data/hot_update_fallback_reboot" 2>/dev/null
	# 管理器可能已经删除暂存目录；用完整副本重建它，确保下次重启仍能标准更新。
	if [ ! -d "$NEW" ] && [ -d "$PAYLOAD" ]; then
		mkdir -p "$NEW" 2>/dev/null
		cp -rfp "$PAYLOAD"/. "$NEW"/ 2>/dev/null || true
	fi
	touch "$OLD/update" 2>/dev/null
	if [ -f "$OLD/bin/common.sh" ]; then
		MODDIR="$OLD"
		. "$OLD/bin/common.sh" 2>/dev/null || true
		if type qsc_write_module_description >/dev/null 2>&1; then
			qsc_write_module_description "⚠️热更新未完成" "请重启设备完成更新" \
				"服务接管校验失败，已保留标准更新流程"
		fi
	fi
	hu_log "fallback: 服务接管校验失败，保留 update 和重启更新源"
}

# 暂存目录的轻量指纹：文件数 + 占用大小
hu_sig() {
	_n="$(find "$NEW" -type f 2>/dev/null | wc -l | tr -d ' ')"
	_k="$(du -sk "$NEW" 2>/dev/null | awk '{print $1}')"
	echo "${_n:-0}:${_k:-0}"
}

hu_verify_file() {
	_src_sum="$(cksum "$1" 2>/dev/null | awk '{print $1":"$2}')"
	_dst_sum="$(cksum "$2" 2>/dev/null | awk '{print $1":"$2}')"
	[ -n "$_src_sum" ] && [ "$_src_sum" = "$_dst_sum" ]
}

hu_version() {
	sed -n 's/^versionCode=//p' "$1" 2>/dev/null | head -n1 | tr -d ' \r'
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
SOURCE_VERSION="$(sed -n 's/^source_version=//p' "$TXN_STATE" 2>/dev/null | head -n1 | tr -d ' \r')"
RUN_VERSION="$(sed -n 's/^target_version=//p' "$TXN_STATE" 2>/dev/null | head -n1 | tr -d ' \r')"
hu_txn_set apply
if [ -d "$PAYLOAD" ]; then
	SRC="$PAYLOAD"
	hu_log "source: 使用管理器目录外的完整副本 $SRC"
else
	SRC="$NEW"
	if ! hu_wait_stable; then
		hu_log "abort: modules_update 未在 60s 内稳定，保留标准更新标记"
		hu_fallback
		exit 1
	fi
fi

[ -d "$SRC" ] || { hu_log "abort: 无更新源 $SRC，保留标准更新标记"; hu_fallback; exit 1; }
[ -d "$OLD" ] || { hu_log "abort: 无 $OLD"; hu_fallback; exit 1; }
[ -f "$OLD/disable" ] && { hu_log "abort: 模块已禁用"; hu_fallback; exit 1; }
[ -f "$OLD/remove" ] && { hu_log "abort: 模块待卸载"; hu_fallback; exit 1; }
# 关键文件齐全才敢覆盖：暂存被中断时不能拿半个包盖掉正在用的模块
for f in module.prop service.sh bin/common.sh hotinstall.sh; do
	[ -f "$SRC/$f" ] || { hu_log "abort: 更新源缺少 $f，保留标准更新标记"; hu_fallback; exit 1; }
done
RUN_VERSION="$(hu_version "$SRC/module.prop")"
case "$RUN_VERSION" in "" | *[!0-9]*) hu_log "abort: 更新源版本号无效，保留标准更新标记"; hu_fallback; exit 1 ;; esac

# 复制新文件前先停止旧 service 与简介 worker，避免旧进程在半更新文件上
# 继续执行，造成「简介首轮成功但停充逻辑失效」的混合版本状态。
_old_worker_pid="$(cat "$OLD/data/description_worker.pid" 2>/dev/null | tr -d ' \r\n')"
_old_heartbeat_pid="$(cat "$OLD/data/service_heartbeat_pid" 2>/dev/null | tr -d ' \r\n')"
case "$_old_worker_pid" in
	""|*[!0-9]*) ;;
	*) kill "$_old_worker_pid" 2>/dev/null || true ;;
esac
case "$_old_heartbeat_pid" in
	""|*[!0-9]*) ;;
	*) kill "$_old_heartbeat_pid" 2>/dev/null || true ;;
esac
pkill -f "$OLD/service.sh" 2>/dev/null || true
pkill -f "$OLD/bin/qsc_switch.sh" 2>/dev/null || true
sleep 1

# 就地覆盖（只增改不删），全程不出现空模块窗口。
# 不使用 cp -a：部分 Android toybox/第三方环境对该短选项兼容性不一致。
_cp_err="$(cp -rfp "$SRC"/. "$OLD"/ 2>&1)"
_cp_rc=$?
if [ "$_cp_rc" -ne 0 ]; then
	hu_log "fail: 覆盖 $OLD 失败 rc=$_cp_rc err=${_cp_err:-无输出}，保留标准更新标记"
	hu_fallback
	exit 1
fi
for f in module.prop service.sh bin/common.sh hotinstall.sh; do
	[ -f "$OLD/$f" ] || {
		hu_log "fail: 覆盖后校验缺少 $f，保留标准更新标记"
		hu_fallback
		exit 1
	}
	hu_verify_file "$SRC/$f" "$OLD/$f" || {
		hu_log "fail: 覆盖后校验不一致 $f，保留标准更新标记"
		hu_fallback
		exit 1
	}
done
hu_log "ok: 已就地覆盖到 $OLD"

# 保留 update/modules_update 直到新 service 的 PID、心跳和主循环均确认稳定。
if [ -f "$OLD/$SCRIPT" ]; then
	if command -v setsid >/dev/null 2>&1; then
		setsid sh "$OLD/$SCRIPT" </dev/null >/dev/null 2>&1 &
	else
		nohup sh "$OLD/$SCRIPT" </dev/null >/dev/null 2>&1 &
	fi
	hu_log "ok: 已启动 $SCRIPT（立即生效，pid $!）"
else
	hu_log "fail: 缺少 $SCRIPT，无法启动新服务"
	hu_fallback
	exit 1
fi

hu_log "handoff: hotinstall 已启动，交给独立 verifier 校验接管"
HOT_UPDATE_WORKER
	chmod 0700 "$_worker_path" 2>/dev/null
}

# 写出并脱离当前会话启动收尾作业。参数: <modid> <hotinstall 脚本名>
hot_update_spawn_worker() {
	_sw_modid="$1"
	_sw_script="${2:-hotinstall.sh}"
	_sw_payload="${3:-/data/adb/qsc/hot_update/payload/$_sw_modid}"
	[ -n "$_sw_modid" ] || return 1
	hot_update_clear_stale_lock "$_sw_modid" || return 1
	# 放在两个模块目录之外：worker 要删掉 modules_update，不能跟着被删；
	# 也不能落在 MODPATH 里，否则会被打包进模块目录
	_sw_path="/data/adb/qsc/hot_update/worker.sh"
	hot_update_write_worker "$_sw_path" || return 1
	# setsid 才能真正脱离安装器的会话；没有就退回 nohup
	if command -v setsid >/dev/null 2>&1; then
		setsid sh "$_sw_path" "$_sw_modid" "$_sw_script" "$_sw_payload" </dev/null >/dev/null 2>&1 &
	else
		nohup sh "$_sw_path" "$_sw_modid" "$_sw_script" "$_sw_payload" </dev/null >/dev/null 2>&1 &
	fi
	return 0
}

hot_update_versioncode() {
	sed -n 's/^versionCode=//p' "$1" 2>/dev/null | head -n1 | tr -d ' \r'
}

hot_update_clear_stale_lock() {
	_stale_lock="/data/adb/qsc/hot_update/lock"
	[ -d "$_stale_lock" ] || return 0
	if [ -f "$_stale_lock/pid" ]; then
		_stale_pid="$(cat "$_stale_lock/pid" 2>/dev/null | tr -d ' \r\n')"
		case "$_stale_pid" in
			""|*[!0-9]*) ;;
			*)
				kill -0 "$_stale_pid" 2>/dev/null && return 1
				rm -rf "$_stale_lock" 2>/dev/null
				[ ! -e "$_stale_lock" ] && return 0
				return 1
				;;
		esac
	fi
	# 兼容旧版留下的空锁目录；有内容但无法确认归属时不强删。
	rmdir "$_stale_lock" 2>/dev/null
}

# 运行期兜底：安装器把我们脱离出去的收尾作业杀掉时，由常驻服务重新拉起。
# 只处理版本号高于当前版本的完整更新源；无法确认时保留 update/modules_update，
# 交给管理器的标准重启流程，绝不擅自删除待更新内容。
# 返回 0 = 做了处理
qsc_hot_finalize() {
	local modid new payload source mine theirs f
	[ -f "$MODDIR/update" ] || [ -d "/data/adb/qsc/hot_update/payload/QSC_Battery" ] || return 1
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
			rmdir /data/adb/qsc/hot_update 2>/dev/null
		fi
		rm -f /data/adb/qsc/hot_update/worker.sh 2>/dev/null
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
