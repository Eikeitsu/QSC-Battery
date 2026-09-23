#!/system/bin/sh
# 统一前台包名总线：LSPosed 写 /data/system/qsc_xp_fg；无 XP / XP 异常时 dumpsys 降级。
# 供简介（管理器列表）、游戏旁路、App 停充等复用。

QSC_FG_XP_PATH="${QSC_FG_XP_PATH:-/data/system/qsc_xp_fg}"
QSC_FG_XP_EDGE_PATH="${QSC_FG_XP_EDGE_PATH:-/data/system/qsc_xp_fg_edge}"
QSC_FG_UNRELIABLE="${DATADIR:-/data/adb/modules/QSC_Battery/data}/xp_fg_unreliable"
QSC_FG_CACHE_AT=0
QSC_FG_CACHE_PKG=""
QSC_FG_CACHE_SEC=12
QSC_FG_PKG=""
QSC_FG_SOURCE=""
QSC_FG_XP_MISMATCH="${QSC_FG_XP_MISMATCH:-0}"

qsc_fg_xp_disabled() {
	[ -f /data/system/qsc_xp_off ] || [ -f /data/system/qsc_xp_no_viewer ] ||
		[ -f /data/system/qsc_xp_write_disabled ]
}

# 前台总线策略空闲（简介/游戏/停充都关）
qsc_fg_xp_policy_idle() {
	[ -f /data/system/qsc_xp_fg_policy ] || return 1
	grep -q '^idle=1' /data/system/qsc_xp_fg_policy 2>/dev/null
}

# 仅表示：已注入且未软关（不一定可信）
qsc_fg_xp_injected() {
	qsc_fg_xp_disabled && return 1
	[ -f /data/system/qsc_xp_alive ] && return 0
	[ -f /data/local/tmp/qsc_xp_alive ] && return 0
	[ -f /cache/qsc_xp_alive ] && return 0
	[ -f "${DATADIR:-}/xp_alive" ] && return 0
	return 1
}

# 可走 XP 事件路径：已注入、未标记不可靠、策略非空闲
qsc_fg_xp_ready() {
	qsc_fg_xp_injected || return 1
	[ -f "${QSC_FG_UNRELIABLE}" ] && return 1
	qsc_fg_xp_policy_idle && return 1
	return 0
}

# 读前台包时是否信任 XP 文件（不 dumpsys）
qsc_fg_xp_trust_file() {
	qsc_fg_xp_ready || return 1
	[ -f "$QSC_FG_XP_PATH" ] || return 1
	return 0
}

qsc_fg_mark_unreliable() {
	local why="$1"
	mkdir -p "${DATADIR:-/data/adb/modules/QSC_Battery/data}" 2>/dev/null
	printf 'at=%s\nwhy=%s\n' "$(date +%s 2>/dev/null)" "${why:-unknown}" \
		>"$QSC_FG_UNRELIABLE" 2>/dev/null
	type qsc_log >/dev/null 2>&1 &&
		qsc_log warn "前台XP异常，回退 dumpsys（${why:-?}）"
}

qsc_fg_clear_unreliable() {
	[ -f "$QSC_FG_UNRELIABLE" ] || return 0
	rm -f "$QSC_FG_UNRELIABLE" 2>/dev/null
	QSC_FG_XP_MISMATCH=0
	type qsc_log >/dev/null 2>&1 &&
		qsc_log info "前台XP已恢复，重新走边沿"
}

# dumpsys 取前台包（贵）；结果缓存 — 提前定义供 health_check 使用
qsc_fg_dumpsys_read() {
	local now focus pkg
	QSC_FG_PKG=""
	now="${QSC_PS_NOW:-0}"
	if [ "$now" -le 0 ] 2>/dev/null; then
		now="$(date +%s 2>/dev/null)"
		case "$now" in ""|*[!0-9]*) now=0 ;; esac
	fi
	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "${QSC_FG_CACHE_AT:-0}" -gt 0 ] 2>/dev/null &&
		[ "$((now - QSC_FG_CACHE_AT))" -lt "${QSC_FG_CACHE_SEC:-12}" ] 2>/dev/null &&
		[ -n "${QSC_FG_CACHE_PKG:-}" ]; then
		QSC_FG_PKG="$QSC_FG_CACHE_PKG"
		QSC_FG_SOURCE=dumpsys_cache
		return 0
	fi
	focus="$(dumpsys window 2>/dev/null | grep 'mCurrentFocus' | tail -1)"
	[ -z "$focus" ] &&
		focus="$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1)"
	[ -n "$focus" ] || return 1
	pkg="$(printf '%s' "$focus" | sed -n 's/.*[[:space:]]\([a-zA-Z0-9._][a-zA-Z0-9._]*\)\/.*/\1/p' | head -n1)"
	[ -n "$pkg" ] ||
		pkg="$(printf '%s' "$focus" | grep -oE '[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+' | head -n1)"
	pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
	[ -n "$pkg" ] || return 1
	QSC_FG_PKG="$pkg"
	QSC_FG_SOURCE=dumpsys
	QSC_FG_CACHE_PKG="$pkg"
	QSC_FG_CACHE_AT="$now"
	return 0
}

# 近 max_age 秒内有前台包名更新（不看 unreliable：边沿本身是恢复信号）
qsc_fg_xp_edge_pending() {
	local f="$QSC_FG_XP_EDGE_PATH" mt now max_age="${1:-30}"
	qsc_fg_xp_disabled && return 1
	[ -f "$f" ] || return 1
	mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
	now="$(date +%s 2>/dev/null || echo 0)"
	case "$mt:$now:$max_age" in *[!0-9:]*) return 1 ;; esac
	[ "$mt" -gt 0 ] 2>/dev/null && [ "$((now - mt))" -le "$max_age" ] 2>/dev/null
}

qsc_fg_xp_consume_edge() {
	qsc_fg_xp_edge_pending || return 1
	rm -f "$QSC_FG_XP_EDGE_PATH" 2>/dev/null || true
	qsc_fg_clear_unreliable
	return 0
}

# 抽样核对：XP fg 与 dumpsys 不一致累计后标不可靠；有边沿/一致则恢复
qsc_fg_xp_health_check() {
	local xp_pkg ds_pkg
	qsc_fg_xp_injected || {
		qsc_fg_mark_unreliable "not_injected"
		return 1
	}
	qsc_fg_xp_disabled && return 1
	qsc_fg_xp_policy_idle && return 1
	# 仅简介（无游戏/停充）时 fg 故意不跟普通 App，不做 mismatch
	if [ -f /data/system/qsc_xp_fg_policy ]; then
		if ! grep -q '^game=1' /data/system/qsc_xp_fg_policy 2>/dev/null &&
			! grep -q '^app_stop=1' /data/system/qsc_xp_fg_policy 2>/dev/null; then
			return 0
		fi
	fi
	if qsc_fg_xp_edge_pending 60; then
		qsc_fg_clear_unreliable
		return 0
	fi
	if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
		qsc_manager_viewer_xp_edge_pending; then
		qsc_fg_clear_unreliable
		return 0
	fi
	xp_pkg=""
	if [ -f "$QSC_FG_XP_PATH" ]; then
		xp_pkg="$(awk -F'\t' 'NF>=2{print $2; exit}' "$QSC_FG_XP_PATH" 2>/dev/null | tr -d ' \r\n')"
	fi
	# 尚无首帧：不判死
	[ -n "$xp_pkg" ] || return 0
	QSC_FG_CACHE_AT=0
	QSC_FG_CACHE_PKG=""
	if ! qsc_fg_dumpsys_read; then
		return 0
	fi
	ds_pkg="$QSC_FG_PKG"
	[ -n "$ds_pkg" ] || return 0
	if [ "$xp_pkg" = "$ds_pkg" ]; then
		QSC_FG_XP_MISMATCH=0
		[ -f "$QSC_FG_UNRELIABLE" ] && qsc_fg_clear_unreliable
		return 0
	fi
	QSC_FG_XP_MISMATCH=$((${QSC_FG_XP_MISMATCH:-0} + 1))
	if [ "${QSC_FG_XP_MISMATCH}" -ge 2 ] 2>/dev/null; then
		qsc_fg_mark_unreliable "mismatch:${xp_pkg}!=${ds_pkg}"
		return 1
	fi
	return 0
}

# 从 XP 状态文件读当前前台包 → QSC_FG_PKG
qsc_fg_xp_read() {
	local f="$QSC_FG_XP_PATH" line pkg
	QSC_FG_PKG=""
	qsc_fg_xp_trust_file || return 1
	IFS= read -r line <"$f" 2>/dev/null || return 1
	pkg="$(printf '%s' "$line" | awk -F'\t' 'NF>=2{print $2; exit}')"
	pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
	case "$pkg" in
		""|*[!a-zA-Z0-9._]*) return 1 ;;
		*.*)
			QSC_FG_PKG="$pkg"
			QSC_FG_SOURCE=xp
			return 0
			;;
		*) return 1 ;;
	esac
}

# 取当前前台包名 → QSC_FG_PKG。信任 XP 则不 dumpsys；否则降级。
qsc_fg_current_pkg() {
	QSC_FG_PKG=""
	QSC_FG_SOURCE=""
	if qsc_fg_xp_read; then
		return 0
	fi
	qsc_fg_dumpsys_read
}

qsc_fg_pkg_in_list() {
	local list_file="$1" pkg
	[ -f "$list_file" ] && [ -s "$list_file" ] || return 1
	qsc_fg_current_pkg || return 1
	pkg="$QSC_FG_PKG"
	[ -n "$pkg" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		line="$(printf '%s' "$line" | tr -d ' \r\n')"
		[ -n "$line" ] || continue
		[ "$line" = "$pkg" ] && return 0
		case "$pkg" in
			"$line"|"$line":*) return 0 ;;
		esac
	done <"$list_file"
	return 1
}

qsc_fg_mtime_token() {
	local f="$QSC_FG_XP_PATH" mt
	[ -f "$f" ] || {
		printf '0'
		return 0
	}
	mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
	case "$mt" in ""|*[!0-9]*) mt=0 ;; esac
	printf '%s' "$mt"
}

# 返回：0=命中 1=未命中 2=应走非 XP 降级
qsc_fg_xp_hit_cached() {
	local cache="$1" tok_file="$2" list_file="$3" tok prev
	[ -n "$cache" ] && [ -n "$tok_file" ] && [ -n "$list_file" ] || return 1
	qsc_fg_xp_trust_file || return 2
	tok="$(qsc_fg_mtime_token)"
	prev="$(cat "$tok_file" 2>/dev/null | tr -d ' \r\n')"
	if [ "$tok" = "$prev" ] && [ -n "$prev" ]; then
		[ -f "$cache" ]
		return $?
	fi
	rm -f "$cache" 2>/dev/null
	if qsc_fg_pkg_in_list "$list_file"; then
		touch "$cache" 2>/dev/null
		printf '%s\n' "$tok" >"$tok_file" 2>/dev/null
		return 0
	fi
	printf '%s\n' "$tok" >"$tok_file" 2>/dev/null
	return 1
}

# 列表命中墓碑会话（游戏/App 停充）：约 1s 稳定进入，确认离开后 30s 宽限。
# 管理器简介会话在 XP 侧另用 3s/90s，不走这里。
# 状态文件：${prefix}.on ${prefix}.last ${prefix}.enter_at
# in_list=1/0；可选第 3 参 sticky_file：业务标记已在（如 app_stop_flag）则跳过进入等待。
# 返回 0=会话命中 1=未命中
QSC_FG_SESSION_ENTER_SEC="${QSC_FG_SESSION_ENTER_SEC:-1}"
QSC_FG_SESSION_LEAVE_SEC="${QSC_FG_SESSION_LEAVE_SEC:-30}"

qsc_fg_session_apply() {
	local prefix="$1" in_list="$2" sticky="${3:-}" now enter_at last
	[ -n "$prefix" ] || return 1
	now="$(date +%s 2>/dev/null)"
	case "$now" in ""|*[!0-9]*) now=0 ;; esac
	[ "$now" -gt 0 ] 2>/dev/null || return 1

	if [ "$in_list" = "1" ]; then
		printf '%s\n' "$now" >"${prefix}.last" 2>/dev/null
		if [ -f "${prefix}.on" ]; then
			rm -f "${prefix}.enter_at" 2>/dev/null
			return 0
		fi
		# 已在停充/限流维持：不要因进入防抖把 latch 松掉
		if [ -n "$sticky" ] && [ -f "$sticky" ]; then
			touch "${prefix}.on" 2>/dev/null
			rm -f "${prefix}.enter_at" 2>/dev/null
			return 0
		fi
		enter_at="$(cat "${prefix}.enter_at" 2>/dev/null | tr -d ' \r\n')"
		case "$enter_at" in ""|*[!0-9]*)
			printf '%s\n' "$now" >"${prefix}.enter_at" 2>/dev/null
			return 1
			;;
		esac
		if [ "$((now - enter_at))" -ge "${QSC_FG_SESSION_ENTER_SEC:-1}" ] 2>/dev/null; then
			touch "${prefix}.on" 2>/dev/null
			rm -f "${prefix}.enter_at" 2>/dev/null
			return 0
		fi
		return 1
	fi

	rm -f "${prefix}.enter_at" 2>/dev/null
	[ -f "${prefix}.on" ] || return 1
	last="$(cat "${prefix}.last" 2>/dev/null | tr -d ' \r\n')"
	case "$last" in ""|*[!0-9]*) last=0 ;; esac
	if [ "$last" -gt 0 ] 2>/dev/null &&
		[ "$((now - last))" -lt "${QSC_FG_SESSION_LEAVE_SEC:-30}" ] 2>/dev/null; then
		return 0
	fi
	rm -f "${prefix}.on" "${prefix}.last" 2>/dev/null
	return 1
}

# 列表是否含当前前台包（XP 优先，否则 dumpsys）
qsc_fg_list_raw_hit() {
	local list_file="$1"
	[ -f "$list_file" ] && [ -s "$list_file" ] || return 1
	qsc_fg_pkg_in_list "$list_file"
}

qsc_fg_focus_text_hit() {
	local list_file="$1" focus="$2" pkg
	[ -n "$focus" ] || return 1
	[ -f "$list_file" ] && [ -s "$list_file" ] || return 1
	while IFS= read -r pkg || [ -n "$pkg" ]; do
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
		[ -n "$pkg" ] || continue
		printf '%s\n' "$focus" | grep -Fq "$pkg" && return 0
	done <"$list_file"
	return 1
}

# 同步 XP 前台门禁：无简介/游戏/停充需求时 idle=1，XP 跳过写盘。
# 游戏限流 / App 停充仅在「已插电」时需要 XP 配合；未插电强制 game=0、app_stop=0。
# 并写出游戏/停充关注包列表，供 XP 分级过滤。
qsc_xp_sync_fg_policy() {
	local desc=0 game=0 stop=0 idle=1 plugged=0
	local list_tmp cc app_on stop_on
	local pol=/data/system/qsc_xp_fg_policy
	local game_pkgs=/data/system/qsc_xp_game_pkgs
	local stop_pkgs=/data/system/qsc_xp_stop_pkgs

	if type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
		plugged=1
	elif [ -n "${battery_powered:-}" ]; then
		plugged=1
	fi

	if type qsc_description_enabled >/dev/null 2>&1 && qsc_description_enabled; then
		desc=1
	fi

	# 游戏 / 停充：功能开且已插电才纳入 XP 关注
	if [ "$plugged" = "1" ]; then
		if [ -f "${CURRENT_CONF:-$CONFDIR/current.json}" ] &&
			type qsc_current_conf_get >/dev/null 2>&1; then
			cc="$(qsc_current_conf_get current_control 2>/dev/null)"
			app_on="$(qsc_current_conf_get app_limit 2>/dev/null)"
			cc="$(qsc_clamp_int "${cc:-0}" 0 1 0)"
			app_on="$(qsc_clamp_int "${app_on:-0}" 0 1 0)"
			if [ "$cc" = "1" ] && [ "$app_on" = "1" ] &&
				type qsc_current_conf_get_strings >/dev/null 2>&1; then
				list_tmp="${DATADIR:-}/.xp_game_pkgs_tmp"
				qsc_current_conf_get_strings app_list >"$list_tmp" 2>/dev/null || : >"$list_tmp"
				if [ -s "$list_tmp" ]; then
					game=1
					sed '/^$/d' "$list_tmp" | sort -u >"$game_pkgs" 2>/dev/null &&
						chmod 0644 "$game_pkgs" 2>/dev/null || true
				fi
				rm -f "$list_tmp" 2>/dev/null
			fi
		fi

		local conf_file="${CONF:-${CONFDIR:-}/config.conf}"
		stop_on="${app_stop:-${QSCV_app_stop:-}}"
		case "$stop_on" in
			"" ) [ -f "$conf_file" ] &&
				stop_on="$(sed -n 's/^app_stop=//p' "$conf_file" 2>/dev/null | head -n1 | tr -d ' \r')" ;;
		esac
		stop_on="$(qsc_clamp_int "${stop_on:-0}" 0 1 0)"
		if [ "$stop_on" = "1" ]; then
			list_tmp="${DATADIR:-}/.xp_stop_pkgs_tmp"
			if [ -n "${app_stop_list:-${QSCV_app_stop_list:-}}" ]; then
				printf '%s' "${app_stop_list:-$QSCV_app_stop_list}" | tr ',; ' '\n' |
					sed '/^$/d' | sort -u >"$list_tmp" 2>/dev/null
			elif [ -f "$conf_file" ]; then
				sed -n 's/^app_stop_list=//p' "$conf_file" 2>/dev/null | head -n1 |
					tr ',; ' '\n' | sed '/^$/d' | sort -u >"$list_tmp" 2>/dev/null
			else
				: >"$list_tmp"
			fi
			if [ -s "$list_tmp" ]; then
				stop=1
				cp -f "$list_tmp" "$stop_pkgs" 2>/dev/null && chmod 0644 "$stop_pkgs" 2>/dev/null || true
			fi
			rm -f "$list_tmp" 2>/dev/null
		fi
	fi
	[ "$game" = "1" ] || rm -f "$game_pkgs" 2>/dev/null
	[ "$stop" = "1" ] || rm -f "$stop_pkgs" 2>/dev/null

	if [ "$desc" = "1" ] || [ "$game" = "1" ] || [ "$stop" = "1" ]; then
		idle=0
	fi

	if [ "$desc" = "1" ] && type qsc_manager_viewer_build_list >/dev/null 2>&1; then
		qsc_manager_viewer_build_list >/dev/null 2>&1 || true
	fi

	printf 'desc=%s\ngame=%s\napp_stop=%s\nplugged=%s\nidle=%s\n' \
		"$desc" "$game" "$stop" "$plugged" "$idle" \
		>"$pol" 2>/dev/null && chmod 0644 "$pol" 2>/dev/null || true

	# XP 热路径只 exists 此文件
	if [ "$idle" = "1" ]; then
		touch /data/system/qsc_xp_fg_idle 2>/dev/null &&
			chmod 0644 /data/system/qsc_xp_fg_idle 2>/dev/null || true
	else
		rm -f /data/system/qsc_xp_fg_idle 2>/dev/null
	fi
}
