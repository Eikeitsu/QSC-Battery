#!/system/bin/sh
# 多设备档案库：每台设备一份压缩快照（含 device.profile、首选开关、检测时间）
# 存放在 $DATADIR/profiles/<slug>.tar.gz；WebUI 可按名称列出/应用/删除
#
# qsc_archive_list               → 每行一条 <slug> （文件名不含 .tar.gz）
# qsc_archive_save <slug>        → 以当前 device.profile 生成档案
# qsc_archive_apply <slug>       → 把档案内 device.profile 还原（保留已测出 preferred_*）
# qsc_archive_delete <slug>      → 删除

QSC_ARCHIVE_DIR="${QSC_ARCHIVE_DIR:-$DATADIR/profiles}"

# slug 必须是安全文件名：小写字母/数字/_/-/点 ；去掉其余
qsc_archive_sanitize() {
	printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

qsc_archive_init() {
	mkdir -p "$QSC_ARCHIVE_DIR" 2>/dev/null
}

qsc_archive_list() {
	qsc_archive_init
	[ -d "$QSC_ARCHIVE_DIR" ] || return 0
	for f in "$QSC_ARCHIVE_DIR"/*.tar.gz; do
		[ -f "$f" ] || continue
		base="${f##*/}"
		printf '%s\n' "${base%.tar.gz}"
	done
}

qsc_archive_save() {
	local raw="$1"
	local slug
	local tmpdir
	[ -f "$DEVICE_PROFILE" ] || return 1
	raw="${raw:-}"
	[ -n "$raw" ] || raw="archive_$(date +%F_%H%M%S)"
	slug="$(qsc_archive_sanitize "$raw")"
	[ -n "$slug" ] || return 1
	qsc_archive_init
	tmpdir="${QSC_ARCHIVE_DIR}/.tmp_$$"
	rm -rf "$tmpdir" 2>/dev/null
	mkdir -p "$tmpdir" 2>/dev/null || return 1
	cp -f "$DEVICE_PROFILE" "$tmpdir/device.profile" 2>/dev/null || {
		rm -rf "$tmpdir"
		return 1
	}
	# 附带上清单缓存：便于 WebUI 立即看到 preferred_switch/model 等字段
	{
		echo "slug=$slug"
		echo "saved_at=$(date +%F_%T)"
		echo "model=$(getprop ro.product.model 2>/dev/null)"
		echo "device=$(getprop ro.product.device 2>/dev/null)"
		echo "marketname=$(getprop ro.product.marketname 2>/dev/null)"
	} >"$tmpdir/manifest"

	(cd "$tmpdir" && tar -czf "${QSC_ARCHIVE_DIR}/${slug}.tar.gz" . manifest device.profile 2>/dev/null)
	_rc=$?
	rm -rf "$tmpdir"
	return $_rc
}

qsc_archive_delete() {
	local raw="$1"
	local slug
	slug="$(qsc_archive_sanitize "$raw")"
	[ -n "$slug" ] || return 1
	rm -f "${QSC_ARCHIVE_DIR}/${slug}.tar.gz" 2>/dev/null
}

qsc_archive_peek() {
	# stdout 以 k=v 打印 manifest + 关键 profile 行（无错误即返回 0）
	local raw="$1" slug tar
	slug="$(qsc_archive_sanitize "$raw")"
	tar="${QSC_ARCHIVE_DIR}/${slug}.tar.gz"
	[ -f "$tar" ] || return 1
	tar -xzOf "$tar" manifest 2>/dev/null || return 1
	# device.profile 里选几行关键项：
	tar -xzOf "$tar" device.profile 2>/dev/null | grep -E '^(mca|mca_path|preferred_|reassert|model|device|marketname)='
}

qsc_archive_apply() {
	# 把档案内 device.profile 覆盖到当前 DATADIR，同时保留原 preferred_*
	local raw="$1" slug tar tmpdir
	slug="$(qsc_archive_sanitize "$raw")"
	tar="${QSC_ARCHIVE_DIR}/${slug}.tar.gz"
	[ -f "$tar" ] || return 1
	qsc_archive_init
	tmpdir="${QSC_ARCHIVE_DIR}/.apply_$$"
	rm -rf "$tmpdir" 2>/dev/null
	mkdir -p "$tmpdir" 2>/dev/null || return 1
	if ! tar -xzf "$tar" -C "$tmpdir" device.profile 2>/dev/null; then
		rm -rf "$tmpdir"
		return 1
	fi
	[ -f "$tmpdir/device.profile" ] || { rm -rf "$tmpdir"; return 1; }
	# 保留本机测出的首选开关（若用户原本已测出）
	local pref_path pref_start pref_stop pref_at
	pref_path="$(qsc_profile_get preferred_switch 2>/dev/null)"
	pref_start="$(qsc_profile_get preferred_start 2>/dev/null)"
	pref_stop="$(qsc_profile_get preferred_stop 2>/dev/null)"
	pref_at="$(qsc_profile_get preferred_tested_at 2>/dev/null)"

	cp -f "$tmpdir/device.profile" "$DEVICE_PROFILE" 2>/dev/null
	_rc=$?
	rm -rf "$tmpdir"
	[ "$_rc" = "0" ] || return 1
	# 如果档案里没有测出过 preferred_*，而本机有，则补回
	if [ -n "$pref_path" ]; then
		qsc_profile_set_key preferred_switch "$pref_path"
		qsc_profile_set_key preferred_start "$pref_start"
		qsc_profile_set_key preferred_stop "$pref_stop"
		qsc_profile_set_key preferred_tested_at "$pref_at"
	fi
	return 0
}
