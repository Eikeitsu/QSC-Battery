#!/system/bin/sh
# 模块管理器「正在看列表」检测：有人前台才勤刷动态简介电量。
# 优先焦点/前台 Activity；失败再弱退回进程命中。结果缓存约 50s。

# 内置常见管理器（Magisk / KSU 系 / APatch 系 / MMRL / WebUI 壳）
# 伴侣 APP 不读 module.prop 简介，故意不列入。
# Magisk 隐藏/随机包名另走 magisk.db requester，不必穷举。
QSC_MANAGER_VIEWER_BUILTIN="
com.topjohnwu.magisk
io.github.vvb2060.magisk
io.github.huskydg.magisk
com.rifsxd.ksunext
me.weishu.kernelsu
com.tiann.kernelsu
com.sukisu.ultra
com.resukisu.resukisu
me.bmax.apatch
me.garfieldhan.apatch.next
me.yuki.folk
com.dergoogler.mmrl
com.dergoogler.mmrl.wx
com.dergoogler.mmrl.ksuwebui
io.github.a13e300.ksuwebui
com.yujincheng1994.wx
"

QSC_MANAGER_VIEWER_CACHE_AT=0
QSC_MANAGER_VIEWER_CACHE_VAL=0
QSC_MANAGER_VIEWER_WAS=0
QSC_MANAGER_VIEWER_LIST="$DATADIR/.manager_viewer_pkgs"
QSC_MANAGER_VIEWER_CACHE_SEC=50

qsc_manager_viewer_extra_pkgs() {
	local v=""
	[ -n "${QSCV_desc_viewer_pkgs:-}" ] && v="$QSCV_desc_viewer_pkgs"
	if [ -z "$v" ] && [ -n "${POWER_CONF:-}" ] && [ -f "$POWER_CONF" ]; then
		v="$(sed -n 's/^desc_viewer_pkgs=//p' "$POWER_CONF" 2>/dev/null | head -n1 | tr -d '\r')"
	fi
	printf '%s' "$v"
}

# 从本机 root 方案尽量解析「官方管理器」包名（冷门/随机包名 Magisk 尤其有用）
qsc_manager_viewer_discovered_pkgs() {
	local pkg="" line

	# Magisk：strings.requester = 当前 Manager（可被隐藏随机包名）
	if command -v magisk >/dev/null 2>&1; then
		line="$(magisk --sqlite "SELECT value FROM strings WHERE key='requester'" 2>/dev/null | head -n1)"
		pkg="${line#value=}"
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
	fi
	if [ -z "$pkg" ] && [ -f /data/adb/magisk.db ]; then
		pkg="$(strings /data/adb/magisk.db 2>/dev/null | grep -oE 'requester[[:cntrl:]]*.*' | head -n1 | sed 's/^requester[^a-zA-Z0-9.]*//')"
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n' | sed 's/[^a-zA-Z0-9._].*$//')"
	fi
	case "$pkg" in
		*[!a-zA-Z0-9._]*|"") ;;
		*.*) printf '%s\n' "$pkg" ;;
	esac

	# APatch：若存在 apd 且支持 package 子命令则尽力读（失败忽略）
	pkg=""
	if command -v apd >/dev/null 2>&1; then
		line="$(apd package 2>/dev/null | head -n1)"
		pkg="$(printf '%s' "$line" | tr -d ' \r\n')"
	fi
	case "$pkg" in
		*[!a-zA-Z0-9._]*|"") ;;
		*.*) printf '%s\n' "$pkg" ;;
	esac

	# KernelSU：无稳定「当前管理器包名」API（按签名识别）；常见 fork 已在 BUILTIN。
	# 部分环境会落盘 uid/包名提示，有则追加。
	for f in /data/adb/ksu/manager_pkg \
		/data/adb/ksu/.manager_pkg \
		/data/adb/ksu/manager; do
		[ -f "$f" ] || continue
		pkg="$(head -n1 "$f" 2>/dev/null | tr -d ' \r\n')"
		case "$pkg" in
			*[!a-zA-Z0-9._]*|"") ;;
			*.*) printf '%s\n' "$pkg" ;;
		esac
	done
}

# 写入一行一个包名的列表文件
qsc_manager_viewer_build_list() {
	local f="${1:-$QSC_MANAGER_VIEWER_LIST}" extra pkg
	mkdir -p "$(dirname "$f")" 2>/dev/null
	{
		printf '%s\n' "$QSC_MANAGER_VIEWER_BUILTIN"
		qsc_manager_viewer_discovered_pkgs
		extra="$(qsc_manager_viewer_extra_pkgs)"
		[ -n "$extra" ] && printf '%s' "$extra" | tr ',; ' '\n'
	} | sed '/^$/d;s/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u >"$f" 2>/dev/null
	[ -s "$f" ]
}

# 焦点/前台是否命中列表中任一包。0=命中
qsc_manager_viewer_focus_hit() {
	local list_file="$1" focus pkg
	[ -f "$list_file" ] && [ -s "$list_file" ] || return 1
	focus="$(dumpsys window 2>/dev/null | grep 'mCurrentFocus' | tail -1)"
	[ -z "$focus" ] &&
		focus="$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1)"
	[ -n "$focus" ] || return 1
	while IFS= read -r pkg || [ -n "$pkg" ]; do
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
		[ -n "$pkg" ] || continue
		printf '%s\n' "$focus" | grep -Fq "$pkg" && return 0
	done <"$list_file"
	return 1
}

# 0=正在看（或弱退回：进程在跑）；结果写入缓存
qsc_manager_viewer_active() {
	local now list_file="${QSC_MANAGER_VIEWER_LIST:-$DATADIR/.manager_viewer_pkgs}"
	now="${QSC_PS_NOW:-0}"
	if [ "$now" -le 0 ] 2>/dev/null; then
		now="$(date +%s 2>/dev/null)"
		case "$now" in ""|*[!0-9]*) now=0 ;; esac
	fi

	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "${QSC_MANAGER_VIEWER_CACHE_AT:-0}" -gt 0 ] 2>/dev/null &&
		[ "$((now - QSC_MANAGER_VIEWER_CACHE_AT))" -lt "${QSC_MANAGER_VIEWER_CACHE_SEC:-50}" ] 2>/dev/null; then
		[ "${QSC_MANAGER_VIEWER_CACHE_VAL:-0}" = "1" ]
		return $?
	fi

	QSC_MANAGER_VIEWER_CACHE_VAL=0
	if qsc_manager_viewer_build_list "$list_file"; then
		if qsc_manager_viewer_focus_hit "$list_file"; then
			QSC_MANAGER_VIEWER_CACHE_VAL=1
		elif type qsc_pkg_proc_hit >/dev/null 2>&1 && qsc_pkg_proc_hit "$list_file"; then
			# dumpsys 失败时弱退回：进程在跑也可能在看 WebUI
			QSC_MANAGER_VIEWER_CACHE_VAL=1
		fi
	fi
	QSC_MANAGER_VIEWER_CACHE_AT="$now"
	[ "${QSC_MANAGER_VIEWER_CACHE_VAL:-0}" = "1" ]
}

# 检测并更新 WAS；返回 0=当前在看。上升沿 RISING=1，离开 FALLING=1
qsc_manager_viewer_poll() {
	local prev="${QSC_MANAGER_VIEWER_WAS:-0}" cur=0
	QSC_MANAGER_VIEWER_RISING=0
	QSC_MANAGER_VIEWER_FALLING=0
	if qsc_manager_viewer_active; then
		cur=1
	fi
	if [ "$cur" = "1" ] && [ "$prev" != "1" ]; then
		QSC_MANAGER_VIEWER_RISING=1
		type qsc_log >/dev/null 2>&1 &&
			qsc_log info "模块管理器在前台（简介将勤刷）"
	elif [ "$cur" != "1" ] && [ "$prev" = "1" ]; then
		QSC_MANAGER_VIEWER_FALLING=1
		type qsc_log >/dev/null 2>&1 &&
			qsc_log info "已离开模块管理器（简介恢复按需）"
	fi
	QSC_MANAGER_VIEWER_WAS="$cur"
	[ "$cur" = "1" ]
}
