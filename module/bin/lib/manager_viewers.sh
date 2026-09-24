#!/system/bin/sh
# 模块管理器「正在看列表」检测：有人前台才缩短动态简介刷新间隔。
# 优先焦点/前台 Activity；失败再弱退回进程命中。结果缓存约 50s。

# 内置常见管理器（Magisk / KSU 系 / APatch 系 / MMRL / WebUI 壳）
# 伴侣 APP 不读 module.prop 简介，故意不列入。
# 随机/隐藏包名：Magisk←requester；KSU/SukiSU←ksud debug package / libksud.so，不必穷举。
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
# 负缓存不宜过长：打开管理器后应尽快命中；正缓存仍靠 worker 观看间隔节流 dumpsys
QSC_MANAGER_VIEWER_CACHE_SEC=12

qsc_manager_viewer_extra_pkgs() {
	local v=""
	[ -n "${QSCV_desc_viewer_pkgs:-}" ] && v="$QSCV_desc_viewer_pkgs"
	if [ -z "$v" ] && [ -n "${POWER_CONF:-}" ] && [ -f "$POWER_CONF" ]; then
		v="$(sed -n 's/^desc_viewer_pkgs=//p' "$POWER_CONF" 2>/dev/null | head -n1 | tr -d '\r')"
	fi
	printf '%s' "$v"
}

# 从本机 root 方案尽量解析「官方管理器」包名（冷门/随机包名尤其有用）
qsc_manager_viewer_discovered_pkgs() {
	local pkg="" line bin so dir base

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

	# KernelSU / SukiSU / KSU Next：
	# 1) ksud debug package → 编译进守护的管理器包名（含 Spoofed/随机包名版）
	# 2) 偶落盘的 manager_pkg 提示文件
	# 3) 已安装 APK 内嵌 libksud.so（轻量扫，兜底）
	pkg=""
	for bin in \
		/data/adb/ksu/bin/ksud \
		/data/adb/ksud \
		/data/adb/ksu/bin/ksu; do
		[ -x "$bin" ] || continue
		line="$("$bin" debug package 2>/dev/null | head -n1)"
		pkg="$(printf '%s' "$line" | tr -d ' \r\n')"
		case "$pkg" in
			*[!a-zA-Z0-9._]*|"") pkg="" ;;
			*.*)
				printf '%s\n' "$pkg"
				pkg=""
				break
				;;
			*) pkg="" ;;
		esac
	done
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
	# libksud.so：Spoofed Manager 几乎必带；路径 …/com.foo.bar-XXXX/lib/…/libksud.so
	# 限制深度与条数，避免刷机扫盘过重
	for so in /data/app/~~*/*/lib/*/libksud.so /data/app/*/lib/*/libksud.so; do
		[ -f "$so" ] || continue
		dir="$(dirname "$(dirname "$(dirname "$so")")")"
		base="${dir##*/}"
		# Android：包名-随机后缀；去掉末段无点后缀
		pkg="$(printf '%s' "$base" | sed 's/-[A-Za-z0-9_=]*$//')"
		case "$pkg" in
			*[!a-zA-Z0-9._]*|"") ;;
			*.*)
				printf '%s\n' "$pkg"
				break
				;;
		esac
	done
}

# 写入一行一个包名的列表文件，并同步到 /data/system 供 LSPosed 边沿 Hook 使用
qsc_manager_viewer_build_list() {
	local f="${1:-$QSC_MANAGER_VIEWER_LIST}" extra pkg
	mkdir -p "$(dirname "$f")" 2>/dev/null
	{
		printf '%s\n' "$QSC_MANAGER_VIEWER_BUILTIN"
		qsc_manager_viewer_discovered_pkgs
		extra="$(qsc_manager_viewer_extra_pkgs)"
		[ -n "$extra" ] && printf '%s' "$extra" | tr ',; ' '\n'
	} | sed '/^$/d;s/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u >"$f" 2>/dev/null
	# XP 读此文件合并包名（隐藏 Magisk 等）；失败忽略
	if [ -s "$f" ]; then
		cp -f "$f" /data/system/qsc_xp_viewer_pkgs 2>/dev/null &&
			chmod 0644 /data/system/qsc_xp_viewer_pkgs 2>/dev/null
	fi
	[ -s "$f" ]
}

# LSPosed 管理器边沿队列是否待处理（非空即待消费；勿用短新鲜窗丢弃，
# 否则 Magisk 一长睡边沿「过期」→ 误跑 dumpsys 兜底、更费电）
qsc_manager_viewer_xp_edge_pending() {
	local f=/data/system/qsc_xp_viewer
	[ -f /data/system/qsc_xp_off ] && return 1
	[ -f /data/system/qsc_xp_no_viewer ] && return 1
	[ -f "$f" ] && [ -s "$f" ]
}

# 跨进程「正在看管理器」标记（按需简介 worker 用）
qsc_desc_viewing_flag() {
	printf '%s' "${DATADIR:-/data/adb/modules/QSC_Battery/data}/description_viewing"
}

qsc_desc_viewing_set() {
	local f
	f="$(qsc_desc_viewing_flag)"
	touch "$f" 2>/dev/null || true
	QSC_MANAGER_VIEWER_WAS=1
}

qsc_desc_viewing_clear() {
	local f
	f="$(qsc_desc_viewing_flag)"
	rm -f "$f" 2>/dev/null || true
	QSC_MANAGER_VIEWER_WAS=0
}

qsc_desc_viewing_active() {
	[ -f "$(qsc_desc_viewing_flag)" ]
}

# 原子消费整段边沿队列：先 mv 再逐行处理，避免 enter 被 leave 覆盖漏掉。
# 返回 0=消费后应视为在看；1=未在看 / 无有效边沿
qsc_manager_viewer_consume_xp_edge() {
	local f=/data/system/qsc_xp_viewer tmp line edge pkg
	local got=0
	QSC_MANAGER_VIEWER_RISING=0
	QSC_MANAGER_VIEWER_FALLING=0
	qsc_manager_viewer_xp_edge_pending || return 1
	tmp="$f.consume.$$"
	mv -f "$f" "$tmp" 2>/dev/null || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] || continue
		edge="$(printf '%s' "$line" | awk -F'\t' 'NF>=2{print $2; exit}')"
		pkg="$(printf '%s' "$line" | awk -F'\t' 'NF>=3{print $3; exit}')"
		edge="$(printf '%s' "$edge" | tr -d ' \r\n')"
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
		case "$edge" in
			enter)
				# 仅当 XP 刚报 screen=off 才丢这条 enter
				if [ -f /data/system/qsc_xp_screen ] &&
					[ -f /data/system/qsc_xp_want_screen ]; then
					_mt="$(stat -c %Y /data/system/qsc_xp_screen 2>/dev/null || echo 0)"
					_now="$(date +%s 2>/dev/null || echo 0)"
					_st="$(awk -F'\t' 'NF{print $NF; exit}' /data/system/qsc_xp_screen 2>/dev/null | tr -d ' \r\n')"
					if [ "$_st" = "off" ] &&
						[ "$_mt" -gt 0 ] 2>/dev/null &&
						[ "$((_now - _mt))" -ge 0 ] 2>/dev/null &&
						[ "$((_now - _mt))" -le 3 ] 2>/dev/null; then
			type qsc_dbg >/dev/null 2>&1 &&
				qsc_dbg "跳过队列中 XP enter（XP 刚报息屏${pkg:+: $pkg}）"
						continue
					fi
				fi
				got=1
				QSC_PS_SCREEN_CACHE_AT=0
				QSC_PS_SCREEN_CACHE_VAL=0
				if [ "${QSC_MANAGER_VIEWER_WAS:-0}" != "1" ]; then
					QSC_MANAGER_VIEWER_RISING=1
					# 默认不写 log.log；开「详细调试日志」可见
					type qsc_dbg >/dev/null 2>&1 &&
						qsc_dbg "模块管理器在前台（XP${pkg:+: $pkg}）"
				else
					type qsc_dbg >/dev/null 2>&1 &&
						qsc_dbg "模块管理器仍在前台（XP 补发${pkg:+: $pkg}）"
				fi
				QSC_MANAGER_VIEWER_WAS=1
				QSC_MANAGER_VIEWER_CACHE_VAL=1
				QSC_MANAGER_VIEWER_CACHE_AT=0
				type qsc_desc_viewing_set >/dev/null 2>&1 && qsc_desc_viewing_set
				;;
			leave)
				got=1
				if [ "${QSC_MANAGER_VIEWER_WAS:-0}" = "1" ] ||
					{ type qsc_desc_viewing_active >/dev/null 2>&1 &&
						qsc_desc_viewing_active; }; then
					QSC_MANAGER_VIEWER_FALLING=1
					type qsc_dbg >/dev/null 2>&1 &&
						qsc_dbg "已离开模块管理器（XP${pkg:+: $pkg}）"
				else
					type qsc_dbg >/dev/null 2>&1 &&
						qsc_dbg "收到 XP leave（本地未在观看${pkg:+: $pkg}）"
				fi
				QSC_MANAGER_VIEWER_WAS=0
				QSC_MANAGER_VIEWER_CACHE_VAL=0
				QSC_MANAGER_VIEWER_CACHE_AT=0
				type qsc_desc_viewing_clear >/dev/null 2>&1 && qsc_desc_viewing_clear
				;;
		esac
	done <"$tmp"
	rm -f "$tmp" 2>/dev/null || true
	# 占位空文件供 inotify；必须 0666，否则 system_server 无法再 append enter
	if [ -d /data/system ]; then
		if type qsc_xp_touch_bus >/dev/null 2>&1; then
			qsc_xp_touch_bus /data/system/qsc_xp_viewer
		else
			: >/data/system/qsc_xp_viewer 2>/dev/null || true
			chmod 0666 /data/system/qsc_xp_viewer 2>/dev/null || true
			rm -f /data/system/qsc_xp_write_disabled 2>/dev/null || true
		fi
	fi
	[ "$got" = "1" ] || return 1
	[ "${QSC_MANAGER_VIEWER_WAS:-0}" = "1" ]
}

# 焦点/前台是否命中列表中任一包。0=命中
qsc_manager_viewer_focus_hit() {
	local list_file="$1"
	[ -f "$list_file" ] && [ -s "$list_file" ] || return 1
	# 统一前台总线：有 XP 读 qsc_xp_fg；无 XP 才 dumpsys
	if type qsc_fg_pkg_in_list >/dev/null 2>&1 && qsc_fg_pkg_in_list "$list_file"; then
		return 0
	fi
	# 仅简介时 XP 仍会给管理器写 fg；文件缺失/空时再 dumpsys 认管理器
	if type qsc_fg_xp_ready >/dev/null 2>&1 && qsc_fg_xp_ready &&
		{ [ ! -f /data/system/qsc_xp_fg ] || [ ! -s /data/system/qsc_xp_fg ]; }; then
		if type qsc_fg_dumpsys_read >/dev/null 2>&1; then
			qsc_fg_dumpsys_read || return 1
			while IFS= read -r _p || [ -n "$_p" ]; do
				_p="$(printf '%s' "$_p" | tr -d ' \r\n')"
				[ -n "$_p" ] || continue
				[ "$_p" = "$QSC_FG_PKG" ] && return 0
			done <"$list_file"
		fi
	fi
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

	# 息屏时不做「在看」判定（dumpsys/残留前台包名极易误报）
	if type qsc_ps_screen_is_off >/dev/null 2>&1 && qsc_ps_screen_is_off; then
		QSC_MANAGER_VIEWER_CACHE_VAL=0
		QSC_MANAGER_VIEWER_CACHE_AT="$now"
		return 1
	fi

	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "${QSC_MANAGER_VIEWER_CACHE_AT:-0}" -gt 0 ] 2>/dev/null &&
		[ "$((now - QSC_MANAGER_VIEWER_CACHE_AT))" -lt "${QSC_MANAGER_VIEWER_CACHE_SEC:-12}" ] 2>/dev/null; then
		[ "${QSC_MANAGER_VIEWER_CACHE_VAL:-0}" = "1" ]
		return $?
	fi

	QSC_MANAGER_VIEWER_CACHE_VAL=0
	if qsc_manager_viewer_build_list "$list_file"; then
		if qsc_manager_viewer_focus_hit "$list_file"; then
			QSC_MANAGER_VIEWER_CACHE_VAL=1
		elif ! type qsc_fg_xp_ready >/dev/null 2>&1 || ! qsc_fg_xp_ready; then
			# 无 XP 时弱退回进程命中（WebUI 壳可能焦点不准）
			if type qsc_pkg_proc_hit >/dev/null 2>&1 && qsc_pkg_proc_hit "$list_file"; then
				QSC_MANAGER_VIEWER_CACHE_VAL=1
			fi
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
	# 先消费 XP 边沿：勿被 Magisk 息屏缓存挡在 consume 之前（enter 已信任 XP）
	if type qsc_manager_viewer_consume_xp_edge >/dev/null 2>&1 &&
		qsc_manager_viewer_xp_edge_pending; then
		if qsc_manager_viewer_consume_xp_edge; then
			type qsc_desc_viewing_set >/dev/null 2>&1 && qsc_desc_viewing_set
			return 0
		fi
		# leave 已消费：视为未在看
		type qsc_desc_viewing_clear >/dev/null 2>&1 && qsc_desc_viewing_clear
		return 1
	fi
	# 息屏：强制视为未在看（并在曾为观看时发离开）
	if type qsc_ps_screen_is_off >/dev/null 2>&1 && qsc_ps_screen_is_off; then
		if [ "$prev" = "1" ] ||
			{ type qsc_desc_viewing_active >/dev/null 2>&1 &&
				qsc_desc_viewing_active; }; then
			QSC_MANAGER_VIEWER_FALLING=1
			QSC_MANAGER_VIEWER_WAS=0
			QSC_MANAGER_VIEWER_CACHE_VAL=0
			type qsc_desc_viewing_clear >/dev/null 2>&1 && qsc_desc_viewing_clear
			type qsc_dbg >/dev/null 2>&1 &&
				qsc_dbg "已离开模块管理器（息屏）"
		fi
		return 1
	fi
	# XP 通用前台：按当前包是否在管理器列表，不 dumpsys
	if type qsc_fg_xp_ready >/dev/null 2>&1 && qsc_fg_xp_ready &&
		type qsc_manager_viewer_build_list >/dev/null 2>&1; then
		qsc_manager_viewer_build_list "${QSC_MANAGER_VIEWER_LIST:-$DATADIR/.manager_viewer_pkgs}" >/dev/null 2>&1 || true
		if type qsc_fg_pkg_in_list >/dev/null 2>&1 &&
			qsc_fg_pkg_in_list "${QSC_MANAGER_VIEWER_LIST:-$DATADIR/.manager_viewer_pkgs}"; then
			cur=1
		fi
	elif qsc_manager_viewer_active; then
		cur=1
	fi
	if [ "$cur" = "1" ] && [ "$prev" != "1" ]; then
		QSC_MANAGER_VIEWER_RISING=1
		type qsc_dbg >/dev/null 2>&1 &&
			qsc_dbg "模块管理器在前台"
	elif [ "$cur" != "1" ] && [ "$prev" = "1" ]; then
		QSC_MANAGER_VIEWER_FALLING=1
		type qsc_dbg >/dev/null 2>&1 &&
			qsc_dbg "已离开模块管理器"
	fi
	QSC_MANAGER_VIEWER_WAS="$cur"
	if [ "$cur" = "1" ]; then
		type qsc_desc_viewing_set >/dev/null 2>&1 && qsc_desc_viewing_set
	else
		type qsc_desc_viewing_clear >/dev/null 2>&1 && qsc_desc_viewing_clear
	fi
	[ "$cur" = "1" ]
}
