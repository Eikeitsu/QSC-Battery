#!/system/bin/sh
# 事件唤醒守护（bin/qscd）的下载 / 切换 / 卸载，供 WebUI 调用。
#
# 用法
#   qscd_fetch.sh status              打印当前状态（KEY=VALUE 行）
#   qscd_fetch.sh check [rust|c]      校验远程版本、哈希与本地二进制
#   qscd_fetch.sh install <rust|c>    从 Pages 下载指定实现并替换当前守护
#   qscd_fetch.sh use <rust|c>        改用模块自带的该实现（不联网）
#   qscd_fetch.sh remove              删除守护并把 native_daemon 置 0
#
# 设计要点：
# - 二进制要以 root 执行，所以必须校验 sha256；校验或自检失败一律回滚，
#   绝不留下一个"能执行但来源不明"的文件。
# - 全程只动 bin/qscd 与 data/native_*，不碰任何充电节点。
# - 输出统一 KEY=VALUE，方便 WebUI 直接解析，避免依赖退出码之外的文案。

MODDIR="${MODDIR:-$(cd "${0%/*}/.." && pwd)}"
. "$MODDIR/bin/common.sh"

PAGES_BASE="${QSCD_PAGES_BASE:-https://eikeitsu.github.io/QSC-Battery}"
MANIFEST_URL="$PAGES_BASE/qscd/manifest.json"
TMPDIR="$DATADIR/.qscd_tmp"
PROGRESS_FILE="$DATADIR/qscd_download_progress"

out() { echo "$1=$2"; }

qscd_progress() {
	mkdir -p "$DATADIR" 2>/dev/null
	_percent="$1"
	_stage="$2"
	printf 'percent=%s\nstage=%s\n' "$_percent" "$_stage" \
		>"$PROGRESS_FILE.tmp.$$" 2>/dev/null &&
		mv -f "$PROGRESS_FILE.tmp.$$" "$PROGRESS_FILE" 2>/dev/null
}

fail() {
	rm -rf "$TMPDIR" 2>/dev/null
	qscd_progress 0 failed
	out ok 0
	out error "$1"
	exit 1
}

# 本机 ABI → 二进制后缀
qscd_arch_suffix() {
	case "$(getprop ro.product.cpu.abi 2>/dev/null)" in
		arm64*) echo "arm64" ;;
		armeabi*) echo "arm" ;;
		*) echo "" ;;
	esac
}

# 下载到标准输出以外的文件；curl 优先，其次 busybox wget
qscd_download() {
	_url="$1"
	_dest="$2"
	rm -f "$_dest" 2>/dev/null
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 15 --max-time 120 -o "$_dest" "$_url" 2>/dev/null \
			&& [ -s "$_dest" ] && return 0
	fi
	if command -v wget >/dev/null 2>&1; then
		wget -q -O "$_dest" "$_url" 2>/dev/null && [ -s "$_dest" ] && return 0
	fi
	if command -v busybox >/dev/null 2>&1; then
		busybox wget -q -O "$_dest" "$_url" 2>/dev/null && [ -s "$_dest" ] && return 0
	fi
	rm -f "$_dest" 2>/dev/null
	return 1
}

qscd_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" 2>/dev/null | awk '{print $1}'
		return 0
	fi
	if command -v busybox >/dev/null 2>&1; then
		busybox sha256sum "$1" 2>/dev/null | awk '{print $1}'
		return 0
	fi
	echo ""
}

# 从 manifest.json 里取某个键；manifest 是扁平结构，够用且不必引入 json 解析
qscd_manifest_get() {
	[ -f "$TMPDIR/manifest.json" ] || return 1
	tr ',{}' '\n' <"$TMPDIR/manifest.json" 2>/dev/null \
		| grep -F "\"$1\"" | head -1 \
		| sed 's/.*:[[:space:]]*"\{0,1\}//; s/"[[:space:]]*$//' \
		| tr -d ' \t\r\n"'
}

qscd_conf_set() {
	_k="$1"
	_v="$2"
	[ -f "$CONF" ] || return 0
	if grep -q "^${_k}=" "$CONF" 2>/dev/null; then
		sed -i "s|^${_k}=.*|${_k}=${_v}|" "$CONF" 2>/dev/null
	else
		echo "${_k}=${_v}" >>"$CONF" 2>/dev/null
	fi
}

qscd_module_version() {
	sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null |
		head -n1 | tr -d ' \r\n'
}

qscd_version_key() {
	printf '%s' "$1" | tr -cd '0-9'
}

qscd_version_compare() {
	awk -F'[.]' -v left="$1" -v right="$2" '
		BEGIN {
			na = split(left, a, "[.]"); nb = split(right, b, "[.]")
			n = (na > nb ? na : nb)
			for (i = 1; i <= n; i++) {
				x = (a[i] == "" ? 0 : a[i]) + 0
				y = (b[i] == "" ? 0 : b[i]) + 0
				if (x < y) { print -1; exit }
				if (x > y) { print 1; exit }
			}
			print 0
		}'
}

qscd_valid_version() {
	_v="$1"
	case "$_v" in
		""|*[!0-9.]*|.*|*.|*..*) return 1 ;;
	esac
	qscd_version_key "$_v" | grep -q '[0-9]'
}

# 换过守护后必须重拉 service.sh：主循环把"等待器不可用"缓存在内存里，
# 且旧进程仍指向被替换掉的 inode。
# 安装期（QSCD_NO_RESTART=1）例外：那时装的是 modules_update 里的副本，
# 服务还没起来，重启只会误杀上一版的进程。
qscd_restart_service() {
	[ "${QSCD_NO_RESTART:-0}" = "1" ] && return 0
	pkill -f "$MODDIR/service.sh" 2>/dev/null
	[ -x "$MODDIR/service.sh" ] || return 0
	(nohup "$MODDIR/service.sh" >/dev/null 2>&1 &) 2>/dev/null
}

# 装好后必须能过 probe，否则说明本机建不起 netlink 套接字，留着也没用
qscd_activate() {
	_src="$1"
	_impl="$2"
	_from="$3"
	_version="$4"
	_candidate="$BINDIR/.qscd.new.$$"

	[ -s "$_src" ] || return 1
	rm -f "$BINDIR"/.qscd.new.* 2>/dev/null
	rm -f "$_candidate" 2>/dev/null
	cp -f "$_src" "$_candidate" 2>/dev/null || {
		rm -f "$_candidate" 2>/dev/null
		return 1
	}
	chmod 0755 "$_candidate" 2>/dev/null
	chown 0:0 "$_candidate" 2>/dev/null
	if ! "$_candidate" probe >/dev/null 2>&1; then
		rm -f "$_candidate" 2>/dev/null
		return 1
	fi
	if ! mv -f "$_candidate" "$BINDIR/qscd" 2>/dev/null; then
		rm -f "$_candidate" 2>/dev/null
		return 1
	fi
	# 换了二进制，之前那个「不可用」与「支持哪些子命令」的判定都作废
	rm -f "$DATADIR/qscd_unusable" "$DATADIR/qscd_features" 2>/dev/null
	echo "$_impl" >"$DATADIR/native_impl_used" 2>/dev/null
	echo "$_from" >"$DATADIR/native_src" 2>/dev/null
	echo "$_version" >"$DATADIR/native_version" 2>/dev/null
	qscd_conf_set native_impl "$_impl"
	qscd_conf_set native_daemon 1
	case "$_impl" in
		c) _impl_label="C" ;;
		*) _impl_label="Rust" ;;
	esac
	qsc_log info "事件等待器已切换为 ${_impl_label} 版（来源：${_from:-unknown}）"
	qscd_restart_service
	return 0
}

cmd_status() {
	_suffix="$(qscd_arch_suffix)"
	out ok 1
	out arch "${_suffix:-unsupported}"
	if [ -x "$BINDIR/qscd" ]; then
		out installed 1
	else
		out installed 0
	fi
	_impl="$(cat "$DATADIR/native_impl_used" 2>/dev/null |
		tr -d ' \r\n' | tr 'A-Z' 'a-z')"
	if [ "$_impl" != "rust" ] && [ "$_impl" != "c" ]; then
		_impl="$(sed -n 's/^native_impl=//p' "$CONF" 2>/dev/null |
			head -n1 | tr -d ' \r\n' | tr 'A-Z' 'a-z')"
	fi
	case "$_impl" in rust|c) ;; *) _impl="" ;; esac
	out impl "$_impl"
	out local_version "$(cat "$DATADIR/native_version" 2>/dev/null | tr -d ' \r\n')"
	out src "$(cat "$DATADIR/native_src" 2>/dev/null | tr -d ' \r\n')"
	# 模块自带的候选（sh 版一个都没有）
	_bundled=""
	[ -f "$BINDIR/qscd-${_suffix}" ] && _bundled="rust"
	if [ -f "$BINDIR/qscdc-${_suffix}" ]; then
		if [ -n "$_bundled" ]; then
			_bundled="rust,c"
		else
			_bundled="c"
		fi
	fi
	out bundled "$_bundled"
	if [ -x "$BINDIR/qscd" ] && "$BINDIR/qscd" probe >/dev/null 2>&1; then
		out probe 1
	else
		out probe 0
	fi
	_selftest_out=""
	_selftest_ok=0
	_features=""
	if [ -x "$BINDIR/qscd" ]; then
		_selftest_out="$("$BINDIR/qscd" selftest 2>/dev/null)"
		[ "$?" -eq 0 ] && _selftest_ok=1
		_features="$("$BINDIR/qscd" features 2>/dev/null | tr -d '\r\n')"
	fi
	out selftest "$_selftest_ok"
	out selftest_netlink "$(printf '%s\n' "$_selftest_out" | sed -n 's/^netlink=//p')"
	out selftest_sysfs "$(printf '%s\n' "$_selftest_out" | sed -n 's/^sysfs=//p')"
	out snapshot_source "$(printf '%s\n' "$_selftest_out" | sed -n 's/^snapshot_source=//p')"
	out snapshot_level "$(printf '%s\n' "$_selftest_out" | sed -n 's/^snapshot_level=//p')"
	out snapshot_temp "$(printf '%s\n' "$_selftest_out" | sed -n 's/^snapshot_temp=//p')"
	out snapshot_failure "$(printf '%s\n' "$_selftest_out" | sed -n 's/^snapshot_failure=//p')"
	out features "$_features"
	out last_wake "$(cat "$DATADIR/qscd_last_wake_reason" 2>/dev/null | tr -d '\r\n')"
	out wait_failure "$(awk -F= '$1 == "reason" { print $2; exit }' "$DATADIR/qscd_unusable" 2>/dev/null)"
	out wait_failure_mode "$(awk -F= '$1 == "mode" { print $2; exit }' "$DATADIR/qscd_unusable" 2>/dev/null)"
	out wait_failure_rc "$(awk -F= '$1 == "rc" { print $2; exit }' "$DATADIR/qscd_unusable" 2>/dev/null)"
	out wait_failure_at "$(awk -F= '$1 == "at" { print $2; exit }' "$DATADIR/qscd_unusable" 2>/dev/null)"
	out wait_failure_time "$(awk -F= '$1 == "time" { print $2; exit }' "$DATADIR/qscd_unusable" 2>/dev/null)"
}

cmd_install() {
	_impl="$1"
	case "$_impl" in
		rust | c) ;;
		*) fail "bad_impl" ;;
	esac
	_suffix="$(qscd_arch_suffix)"
	[ -n "$_suffix" ] || fail "unsupported_arch"

	qscd_progress 5 prepare
	mkdir -p "$TMPDIR" 2>/dev/null
	rm -f "$TMPDIR/manifest.json" "$TMPDIR/qscd" 2>/dev/null

	qscd_progress 15 manifest
	qscd_download "$MANIFEST_URL" "$TMPDIR/manifest.json" || fail "manifest_download_failed"

	_name="qscd-${_impl}-${_suffix}"
	_want="$(qscd_manifest_get "$_name" | tr 'A-F' 'a-f')"
	[ -n "$_want" ] || fail "manifest_no_entry"
	_remote_version="$(qscd_manifest_get version)"
	qscd_valid_version "$_remote_version" || fail "manifest_invalid_version"
	_sha_len="$(printf '%s' "$_want" | wc -c | tr -d ' ')"
	case "$_want" in *[!0-9a-fA-F]*) fail "manifest_invalid_sha256" ;; esac
	[ "$_sha_len" = "64" ] || fail "manifest_invalid_sha256"

	qscd_progress 35 binary
	qscd_download "$PAGES_BASE/qscd/$_name" "$TMPDIR/qscd" || fail "download_failed"

	qscd_progress 65 verify
	_got="$(qscd_sha256 "$TMPDIR/qscd")"
	[ -n "$_got" ] || fail "no_sha256_tool"
	if [ "$_got" != "$_want" ]; then
		rm -f "$TMPDIR/qscd" 2>/dev/null
		fail "sha256_mismatch"
	fi

	qscd_progress 82 activate
	if ! qscd_activate "$TMPDIR/qscd" "$_impl" download "$_remote_version"; then
		rm -rf "$TMPDIR" 2>/dev/null
		fail "probe_failed"
	fi
	rm -rf "$TMPDIR" 2>/dev/null
	qscd_progress 100 "done"
	out ok 1
	out impl "$_impl"
	out src download
	out version "$_remote_version"
}

cmd_use() {
	_impl="$1"
	_suffix="$(qscd_arch_suffix)"
	[ -n "$_suffix" ] || fail "unsupported_arch"
	case "$_impl" in
		rust) _src="$BINDIR/qscd-${_suffix}" ;;
		c) _src="$BINDIR/qscdc-${_suffix}" ;;
		*) fail "bad_impl" ;;
	esac
	[ -f "$_src" ] || fail "not_bundled"
	qscd_progress 35 activate
	_local_version="$(qscd_module_version)"
	qscd_valid_version "$_local_version" || _local_version=""
	qscd_activate "$_src" "$_impl" bundled "$_local_version" || fail "probe_failed"
	qscd_progress 100 "done"
	out ok 1
	out impl "$_impl"
	out src bundled
}

cmd_remove() {
	rm -f "$BINDIR/qscd" "$DATADIR/native_impl_used" "$DATADIR/native_src" \
		"$DATADIR/native_version" 2>/dev/null
	rm -f "$PROGRESS_FILE" 2>/dev/null
	qscd_conf_set native_daemon 0
	qscd_restart_service
	out ok 1
	out installed 0
}

cmd_check() {
	_impl="$1"
	[ -n "$_impl" ] || _impl="$(cat "$DATADIR/native_impl_used" 2>/dev/null |
		tr -d ' \r\n' | tr 'A-Z' 'a-z')"
	case "$_impl" in rust|c) ;; *) fail "bad_impl" ;; esac
	_suffix="$(qscd_arch_suffix)"
	[ -n "$_suffix" ] || fail "unsupported_arch"
	qscd_progress 10 manifest
	mkdir -p "$TMPDIR" 2>/dev/null
	rm -f "$TMPDIR/manifest.json" 2>/dev/null
	qscd_download "$MANIFEST_URL" "$TMPDIR/manifest.json" || fail "manifest_download_failed"
	_remote_version="$(qscd_manifest_get version)"
	qscd_valid_version "$_remote_version" || fail "manifest_invalid_version"
	_name="qscd-${_impl}-${_suffix}"
	_remote_hash="$(qscd_manifest_get "$_name" | tr 'A-F' 'a-f')"
	[ -n "$_remote_hash" ] || fail "manifest_no_entry"
	_hash_len="$(printf '%s' "$_remote_hash" | wc -c | tr -d ' ')"
	case "$_remote_hash" in *[!0-9a-f]*) fail "manifest_invalid_sha256" ;; esac
	[ "$_hash_len" = "64" ] || fail "manifest_invalid_sha256"
	_local_version="$(cat "$DATADIR/native_version" 2>/dev/null | tr -d ' \r\n')"
	_local_hash=""
	[ -f "$BINDIR/qscd" ] && _local_hash="$(qscd_sha256 "$BINDIR/qscd")"
	_hash_match=0
	[ -n "$_local_hash" ] && [ "$_local_hash" = "$_remote_hash" ] && _hash_match=1
	_state=unknown
	_update=0
	if qscd_valid_version "$_local_version"; then
		case "$(qscd_version_compare "$_remote_version" "$_local_version")" in
			0) _state=same ;;
			1) _state=update; _update=1 ;;
			-1) _state=local_newer ;;
		esac
	fi
	# 版本号相同但文件被替换/损坏时也必须允许重新下载修复，不能只显示
	# 「版本相同」却把用户锁在当前二进制上。
	if [ -f "$BINDIR/qscd" ] && [ "$_hash_match" != "1" ]; then
		_update=1
	fi
	rm -rf "$TMPDIR" 2>/dev/null
	qscd_progress 100 "done"
	out ok 1
	out impl "$_impl"
	out local_version "$_local_version"
	out remote_version "$_remote_version"
	out version_state "$_state"
	out update_available "$_update"
	out hash_match "$_hash_match"
}

case "$1" in
	status) cmd_status ;;
	check) cmd_check "$2" ;;
	install) cmd_install "$2" ;;
	use) cmd_use "$2" ;;
	remove) cmd_remove ;;
	*)
		out ok 0
		out error "usage"
		exit 1
		;;
esac
