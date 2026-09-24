#!/system/bin/sh
# 分级省电策略：档位 × 息屏/夜间/深睡；停充维持亦可按场景拉长（MCA 除外）

QSC_PS_PROFILE=balanced
QSC_PS_SCREEN_OFF_SAVER=1
QSC_PS_NIGHT_SAVER=0
QSC_PS_DEEP_ENABLE=1
QSC_PS_DEEP_AFTER=600
QSC_PS_DEEP_IDLE=900
QSC_PS_DEEP_FULL_GAP=7200
QSC_PS_HB_SEC=180
QSC_PS_SCREEN_DUMPSYS=0
# 连续息屏满此秒数才切到 screen_off 模式（防亮灭闪动刷日志/抖策略）
QSC_PS_SCREEN_OFF_ENTER=90
# 驻停不足此秒数退出时不写 INFO 总结（仍结束段）
QSC_PS_PARK_MIN_SUMMARY=180

# 运行态（qsc_ps_policy_refresh 填写）
QSC_PS_MODE=active
QSC_PS_MODE_WAS=
QSC_PS_SCREEN_OFF=0
QSC_PS_NIGHT=0
QSC_PS_DEEP=0
QSC_PS_DESC_FORCE_STATIC=0
QSC_PS_SCREEN_OFF_SINCE=0
QSC_PS_SCREEN_CACHE_AT=0
QSC_PS_SCREEN_CACHE_VAL=0
QSC_PS_MAINTAIN_EFF=30

# 息屏/夜间/深睡驻停段（三者重合时合成一段，退出才总结）
QSC_PS_PARK_ACTIVE=0
QSC_PS_PARK_LABEL=
QSC_PS_PARK_SINCE=0
QSC_PS_PARK_WAKES0=0
QSC_PS_PARK_LOOPS0=0
QSC_PS_PARK_SKIPS0=0
QSC_PS_PARK_FULL0=0
QSC_PS_PARK_SLEEP_SUM0=0
QSC_PS_PARK_SLEEP_N0=0
QSC_PS_PARK_DESC_W0=0
QSC_PS_PARK_LAST_SUMMARY=

qsc_ps_apply_profile_defaults() {
	case "${QSC_PS_PROFILE:-balanced}" in
		aggressive)
			[ "${QSC_PS_IDLE_NATIVE_SET:-0}" = "1" ] || QSC_PS_IDLE_NATIVE=900
			[ "${QSC_PS_HB_SET:-0}" = "1" ] || QSC_PS_HB_SEC=600
			QSC_PS_FULL_MAX_GAP=3600
			QSC_PS_DESC_FORCE_STATIC=1
			;;
		custom)
			QSC_PS_FULL_MAX_GAP=1800
			QSC_PS_DESC_FORCE_STATIC=0
			;;
		balanced|*)
			[ "${QSC_PS_IDLE_NATIVE_SET:-0}" = "1" ] || QSC_PS_IDLE_NATIVE=600
			[ "${QSC_PS_HB_SET:-0}" = "1" ] || QSC_PS_HB_SEC=180
			QSC_PS_FULL_MAX_GAP=1800
			QSC_PS_DESC_FORCE_STATIC=0
			;;
	esac
}

# 廉价息屏探测；失败视为亮屏。优先读 XP 亮灭屏边沿（opt-in）；否则 sysfs，缓存 60s。
qsc_ps_screen_is_off() {
	local now="${QSC_PS_NOW:-0}" p v f line state mt age
	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "$now" = "${QSC_PS_SCREEN_CACHE_AT:-}" ]; then
		[ "${QSC_PS_SCREEN_CACHE_VAL:-0}" = "1" ]
		return $?
	fi
	# XP 亮灭屏：want_screen 且边沿文件新鲜时跳过 sysfs 缓存窗口
	if [ -f /data/system/qsc_xp_want_screen ] &&
		[ ! -f /data/system/qsc_xp_off ] &&
		[ -f /data/system/qsc_xp_screen ]; then
		f=/data/system/qsc_xp_screen
		mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
		case "$mt:$now" in *[!0-9:]*) ;;
		*)
			age=$((now - mt))
			if [ "$mt" -gt 0 ] 2>/dev/null && [ "$age" -ge 0 ] 2>/dev/null &&
				[ "$age" -le 15 ] 2>/dev/null; then
				IFS= read -r line <"$f" 2>/dev/null || line=
				state="$(printf '%s' "$line" | awk -F'\t' 'NF{print $NF; exit}' | tr -d ' \r\n')"
				case "$state" in
					off)
						QSC_PS_SCREEN_CACHE_VAL=1
						QSC_PS_SCREEN_CACHE_AT="$now"
						return 0
						;;
					on)
						QSC_PS_SCREEN_CACHE_VAL=0
						QSC_PS_SCREEN_CACHE_AT="$now"
						return 1
						;;
				esac
			fi
			;;
		esac
	fi
	# sysfs 缓存不宜过长：亮屏后若仍沿用息屏结果，会把 XP enter 误判丢掉
	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "$((now - ${QSC_PS_SCREEN_CACHE_AT:-0}))" -lt 8 ] 2>/dev/null; then
		[ "${QSC_PS_SCREEN_CACHE_VAL:-0}" = "1" ]
		return $?
	fi

	QSC_PS_SCREEN_CACHE_VAL=0
	for p in /sys/class/backlight/*/brightness \
		/sys/class/leds/lcd-backlight/brightness \
		/sys/devices/virtual/graphics/fb0/blank; do
		[ -r "$p" ] || continue
		IFS= read -r v <"$p" 2>/dev/null || continue
		v="$(printf '%s' "$v" | tr -d ' \r\n')"
		case "$v" in
			""|*[!0-9]*) continue ;;
		esac
		case "$p" in
			*/blank)
				[ "$v" != "0" ] && QSC_PS_SCREEN_CACHE_VAL=1
				;;
			*)
				[ "$v" = "0" ] && QSC_PS_SCREEN_CACHE_VAL=1
				;;
		esac
		break
	done

	if [ "${QSC_PS_SCREEN_CACHE_VAL:-0}" != "1" ] &&
		[ "${QSC_PS_SCREEN_DUMPSYS:-0}" = "1" ] &&
		command -v dumpsys >/dev/null 2>&1; then
		if dumpsys power 2>/dev/null | grep -Eq 'mHoldingDisplaySuspendBlocker=false|Display Power: state=OFF|state=OFF'; then
			QSC_PS_SCREEN_CACHE_VAL=1
		fi
	fi

	QSC_PS_SCREEN_CACHE_AT="$now"
	[ "${QSC_PS_SCREEN_CACHE_VAL:-0}" = "1" ]
}

qsc_ps_night_active() {
	local range start end line
	[ "${QSC_PS_NIGHT_SAVER:-0}" = "1" ] || return 1
	[ -f "${POWER_CONF:-}" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		range="$(printf '%s' "$line" | sed 's/^night_schedule=//;s/^\[//;s/\]$//' | tr -d ' \r\n')"
		[ -n "$range" ] || continue
		case "$range" in
			*-*-*) continue ;;
			*-*)
				start="${range%%-*}"
				end="${range#*-}"
				type qsc_time_in_range >/dev/null 2>&1 &&
					qsc_time_in_range "$start" "$end" && return 0
				;;
		esac
	done <<EOF
$(grep '^night_schedule=' "$POWER_CONF" 2>/dev/null)
EOF
	return 1
}

# 刷新息屏/夜间/深睡标记（插电停充路径也会用到，不可因 plugged 跳过）
qsc_ps_policy_scene() {
	local now="${QSC_PS_NOW:-0}" screen_off=0 night=0 deep=0

	QSC_PS_SCREEN_OFF=0
	QSC_PS_NIGHT=0
	QSC_PS_DEEP=0

	if [ "${QSC_PS_SCREEN_OFF_SAVER:-0}" = "1" ] && qsc_ps_screen_is_off; then
		screen_off=1
		QSC_PS_SCREEN_OFF=1
		if [ "${QSC_PS_SCREEN_OFF_SINCE:-0}" -le 0 ] 2>/dev/null; then
			QSC_PS_SCREEN_OFF_SINCE="$now"
		fi
	else
		QSC_PS_SCREEN_OFF_SINCE=0
	fi

	if qsc_ps_night_active; then
		night=1
		QSC_PS_NIGHT=1
	fi

	if [ "$night" = "1" ]; then
		deep=1
	elif [ "${QSC_PS_DEEP_ENABLE:-0}" = "1" ] && [ "$screen_off" = "1" ] &&
		[ "$now" -gt 0 ] 2>/dev/null &&
		[ "${QSC_PS_SCREEN_OFF_SINCE:-0}" -gt 0 ] 2>/dev/null &&
		[ "$((now - QSC_PS_SCREEN_OFF_SINCE))" -ge "${QSC_PS_DEEP_AFTER:-600}" ] 2>/dev/null; then
		deep=1
	fi
	[ "$deep" = "1" ] && QSC_PS_DEEP=1
	return 0
}

# 停充维持有效间隔：MCA 不拉长；非 MCA 息屏/夜间/深睡可拉长以便 Doze
# 结果写入 QSC_PS_MAINTAIN_EFF
qsc_ps_maintain_secs() {
	local base="${QSC_PS_MAINTAIN:-30}"
	base="$(qsc_clamp_int "$base" 3 600 30)"
	QSC_PS_MAINTAIN_EFF="$base"

	type qsc_ps_policy_scene >/dev/null 2>&1 && qsc_ps_policy_scene

	# MCA：必须按时重申，不受场景拉长
	if type qsc_device_is_mca >/dev/null 2>&1 && qsc_device_is_mca; then
		return 0
	fi

	if [ "${QSC_PS_DEEP:-0}" = "1" ] || [ "${QSC_PS_NIGHT:-0}" = "1" ]; then
		QSC_PS_MAINTAIN_EFF=300
		[ "$base" -gt 300 ] 2>/dev/null && QSC_PS_MAINTAIN_EFF="$base"
		# 若仍持内核锁，可再保守一点到 300（已是）；用户手调更大则尊重
		QSC_PS_MAINTAIN_EFF="$(qsc_clamp_int "$QSC_PS_MAINTAIN_EFF" 60 600 300)"
		return 0
	fi
	if [ "${QSC_PS_SCREEN_OFF:-0}" = "1" ]; then
		QSC_PS_MAINTAIN_EFF=180
		[ "$base" -gt 180 ] 2>/dev/null && QSC_PS_MAINTAIN_EFF="$base"
		QSC_PS_MAINTAIN_EFF="$(qsc_clamp_int "$QSC_PS_MAINTAIN_EFF" 60 600 180)"
		return 0
	fi
	# 亮屏日用：用配置 maintain（偏勤，便于看简介/状态）
	return 0
}

# auto 持锁是否应在此刻持有：仅息屏（或探测失败偏安全？→ 亮屏释放更利 Doze 日用）
# 深睡回充风险主要在息屏；亮屏时释放，让系统可 idle。
# 返回 0=应该持锁
qsc_ps_wakelock_screen_wants_hold() {
	type qsc_ps_policy_scene >/dev/null 2>&1 && qsc_ps_policy_scene
	# 息屏或夜间：持锁
	[ "${QSC_PS_SCREEN_OFF:-0}" = "1" ] && return 0
	[ "${QSC_PS_NIGHT:-0}" = "1" ] && return 0
	# 亮屏：不持锁
	return 1
}

# 当前是否处于「省电驻停」场景（息屏/夜间/深睡；重合算一段）
qsc_ps_park_tier() {
	# 输出: deep|night|screen_off|（空=非驻停）
	case "${QSC_PS_MODE:-}" in
		deep)
			if [ "${QSC_PS_NIGHT:-0}" = "1" ]; then
				printf '%s' "night"
			else
				printf '%s' "deep"
			fi
			return 0
			;;
		screen_off)
			printf '%s' "screen_off"
			return 0
			;;
		maintain)
			if [ "${QSC_PS_NIGHT:-0}" = "1" ]; then
				printf '%s' "night"
				return 0
			fi
			if [ "${QSC_PS_DEEP:-0}" = "1" ]; then
				printf '%s' "deep"
				return 0
			fi
			if [ "${QSC_PS_SCREEN_OFF:-0}" = "1" ]; then
				printf '%s' "screen_off"
				return 0
			fi
			;;
	esac
	printf ''
	return 1
}

qsc_ps_park_label_zh() {
	case "$1" in
		night) printf '%s' "夜间深睡" ;;
		deep) printf '%s' "息屏深睡" ;;
		screen_off) printf '%s' "息屏加强" ;;
		*) printf '%s' "${1:-驻停}" ;;
	esac
}

qsc_ps_park_session_begin() {
	local label="$1" now="${QSC_PS_NOW:-0}" zh
	QSC_PS_PARK_ACTIVE=1
	QSC_PS_PARK_LABEL="$label"
	QSC_PS_PARK_SINCE="$now"
	QSC_PS_PARK_WAKES0="${QSC_PS_WAKE_COUNT:-0}"
	QSC_PS_PARK_LOOPS0="${QSC_SERVICE_LOOP_COUNT:-0}"
	QSC_PS_PARK_SKIPS0="${QSC_SERVICE_SKIP_ROUNDS:-0}"
	QSC_PS_PARK_FULL0="${QSC_SERVICE_FULL_ROUNDS:-0}"
	QSC_PS_PARK_SLEEP_SUM0="${QSC_PS_SLEEP_SEC_SUM:-0}"
	QSC_PS_PARK_SLEEP_N0="${QSC_PS_SLEEP_COUNT:-0}"
	QSC_PS_PARK_DESC_W0="${QSC_PS_DESC_WRITES:-0}"
	zh="$(qsc_ps_park_label_zh "$label")"
	qsc_log debug "进入${zh}（目标少唤醒；idle≈${QSC_PS_IDLE_EFF:-?}s）"
}

qsc_ps_park_session_end() {
	local now="${QSC_PS_NOW:-0}" label="${QSC_PS_PARK_LABEL:-}" zh
	local elapsed wakes loops skips full sleep_sum sleep_n desc_w
	local avg_sleep wph verdict mins _wph_a _wph_b

	[ "${QSC_PS_PARK_ACTIVE:-0}" = "1" ] || return 0
	case "$now" in ""|*[!0-9]*) now=0 ;; esac
	elapsed=$((now - ${QSC_PS_PARK_SINCE:-0}))
	[ "$elapsed" -lt 1 ] 2>/dev/null && elapsed=1

	wakes=$((${QSC_PS_WAKE_COUNT:-0} - ${QSC_PS_PARK_WAKES0:-0}))
	loops=$((${QSC_SERVICE_LOOP_COUNT:-0} - ${QSC_PS_PARK_LOOPS0:-0}))
	skips=$((${QSC_SERVICE_SKIP_ROUNDS:-0} - ${QSC_PS_PARK_SKIPS0:-0}))
	full=$((${QSC_SERVICE_FULL_ROUNDS:-0} - ${QSC_PS_PARK_FULL0:-0}))
	sleep_sum=$((${QSC_PS_SLEEP_SEC_SUM:-0} - ${QSC_PS_PARK_SLEEP_SUM0:-0}))
	sleep_n=$((${QSC_PS_SLEEP_COUNT:-0} - ${QSC_PS_PARK_SLEEP_N0:-0}))
	desc_w=$((${QSC_PS_DESC_WRITES:-0} - ${QSC_PS_PARK_DESC_W0:-0}))
	[ "$wakes" -lt 0 ] 2>/dev/null && wakes=0
	[ "$loops" -lt 0 ] 2>/dev/null && loops=0
	[ "$skips" -lt 0 ] 2>/dev/null && skips=0
	[ "$full" -lt 0 ] 2>/dev/null && full=0
	[ "$sleep_sum" -lt 0 ] 2>/dev/null && sleep_sum=0
	[ "$sleep_n" -lt 0 ] 2>/dev/null && sleep_n=0
	[ "$desc_w" -lt 0 ] 2>/dev/null && desc_w=0

	avg_sleep=0
	[ "$sleep_n" -gt 0 ] 2>/dev/null && avg_sleep=$((sleep_sum / sleep_n))
	wph=$((wakes * 36000 / elapsed))
	_wph_a=$((wph / 10))
	_wph_b=$((wph % 10))

	if [ "$avg_sleep" -ge 500 ] 2>/dev/null || [ "$wakes" -eq 0 ] ||
		[ "$((wakes * 3600))" -le "$((8 * elapsed))" ] 2>/dev/null; then
		verdict="接近少唤醒待机"
	elif [ "$avg_sleep" -ge 180 ] 2>/dev/null; then
		verdict="中等（可再查 qscd/持锁）"
	else
		verdict="唤醒偏勤"
	fi

	zh="$(qsc_ps_park_label_zh "$label")"
	mins=$((elapsed / 60))
	[ "$mins" -lt 1 ] 2>/dev/null && mins=1
	QSC_PS_PARK_LAST_SUMMARY="退出${zh} ${mins}m：唤醒${wakes}次(≈${_wph_a}.${_wph_b}/h) skip ${skips}/${loops} 满轮${full} 均睡${avg_sleep}s 简介写${desc_w} → ${verdict}"
	# 过短驻停（常见于亮灭闪动）不刷 INFO，避免误导且少写盘
	# 深睡段即使略短也写 INFO（用户更关心过夜总结）
	_min="${QSC_PS_PARK_MIN_SUMMARY:-180}"
	case "$label" in
		deep|night) [ "$_min" -gt 60 ] 2>/dev/null && _min=60 ;;
	esac
	if [ "$elapsed" -lt "$_min" ] 2>/dev/null; then
		qsc_log debug "短驻停忽略总结（${elapsed}s<${_min}s）: $QSC_PS_PARK_LAST_SUMMARY"
	else
		qsc_log info "$QSC_PS_PARK_LAST_SUMMARY"
		printf '%s\n' "$QSC_PS_PARK_LAST_SUMMARY" >"$DATADIR/park_last_summary" 2>/dev/null
	fi

	QSC_PS_PARK_ACTIVE=0
	QSC_PS_PARK_LABEL=
	QSC_PS_PARK_SINCE=0
}

# 在 policy_refresh 末尾调用：边沿日志 + 驻停段总结 + 简介 worker 门禁
qsc_ps_policy_edge_log() {
	local prev="${QSC_PS_MODE_WAS:-}" cur="${QSC_PS_MODE:-}"
	local tier new_park=0 zh

	tier="$(qsc_ps_park_tier)"
	[ -n "$tier" ] && new_park=1

	if [ -n "$prev" ] && [ "$prev" != "$cur" ]; then
		case "$prev:$cur" in
			screen_off:deep|deep:screen_off)
				qsc_log debug "省电档切换 ${prev}→${cur}（同属驻停段）"
				;;
			*)
				case "$cur" in
					deep|screen_off) ;;
					*)
						case "$prev" in
							deep|screen_off) ;;
							*)
								qsc_log debug "运行模式 ${prev}→${cur}"
								;;
						esac
						;;
				esac
				;;
		esac
	fi

	if [ "$new_park" = "1" ]; then
		QSC_PS_PARK_EXIT_SINCE=0
		QSC_PS_DEEP_EXIT_HITS=0
		if [ "${QSC_PS_PARK_ACTIVE:-0}" != "1" ]; then
			qsc_ps_park_session_begin "$tier"
			# 进入息屏加强/深睡：停简介 worker，少一个常驻 shell
			type qsc_stop_description_worker >/dev/null 2>&1 &&
				qsc_stop_description_worker
			type qsc_description_restore_static >/dev/null 2>&1 &&
				qsc_description_restore_static
		elif [ -n "$tier" ] && [ "$tier" != "${QSC_PS_PARK_LABEL:-}" ]; then
			zh="$(qsc_ps_park_label_zh "$tier")"
			qsc_log debug "驻停加深为${zh}"
			QSC_PS_PARK_LABEL="$tier"
		fi
	else
		if [ "${QSC_PS_PARK_ACTIVE:-0}" = "1" ]; then
			qsc_ps_park_session_end
			# 离开驻停：按需拉起（有 enter/观看才要）
			if type qsc_ps_desc_worker_wanted >/dev/null 2>&1 &&
				qsc_ps_desc_worker_wanted; then
				type qsc_start_description_worker >/dev/null 2>&1 &&
					qsc_start_description_worker
			fi
		fi
	fi

	QSC_PS_MODE_WAS="$cur"
}

# 深睡粘滞：跳过息屏 sysfs 探测，沿用 deep idle。
# 每隔 QSC_PS_DEEP_STICKY_MAX（默认 2）次 lean 醒做一次全量场景刷新。
# 退出深睡需连续两次全量探测都非 deep（防亮度抖动误退出 → 反复启停 worker）。
# 返回 0=已粘滞处理；1=需走全量 policy_refresh
qsc_ps_policy_try_deep_sticky() {
	local max="${QSC_PS_DEEP_STICKY_MAX:-2}" n
	case "${QSC_PS_MODE_WAS:-}" in
		deep) ;;
		*) return 1 ;;
	esac
	[ "${QSC_PS_CONF_RELOADED:-0}" = "1" ] && return 1
	case "$max" in ""|*[!0-9]*) max=2 ;; esac
	[ "$max" -lt 1 ] 2>/dev/null && max=1
	n=$((${QSC_PS_DEEP_STICKY_N:-0} + 1))
	QSC_PS_DEEP_STICKY_N="$n"
	if [ $((n % (max + 1))) -eq 0 ] 2>/dev/null; then
		return 1
	fi
	QSC_PS_MODE=deep
	QSC_PS_DEEP=1
	QSC_PS_SCREEN_OFF=1
	QSC_PS_DESC_FORCE_STATIC=1
	QSC_PS_IDLE_EFF="${QSC_PS_DEEP_IDLE:-900}"
	QSC_PS_FULL_MAX_GAP="${QSC_PS_DEEP_FULL_GAP:-7200}"
	QSC_PS_HB_SEC="$(qsc_clamp_int "${QSC_PS_HB_SEC:-180}" 180 900 600)"
	QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
	return 0
}

# 若本应从驻停退出，先滞回一段时间（默认=screen_off_enter_sec），避免亮灭闪一下就结算总结/拉 worker
qsc_ps_policy_hold_park_exit() {
	local now="${QSC_PS_NOW:-0}" need="${QSC_PS_SCREEN_OFF_ENTER:-90}" since
	case "$need" in ""|*[!0-9]*) need=90 ;; esac
	[ "$need" -lt 30 ] 2>/dev/null && need=30
	since="${QSC_PS_PARK_EXIT_SINCE:-0}"
	if [ "$since" -le 0 ] 2>/dev/null; then
		QSC_PS_PARK_EXIT_SINCE="$now"
		return 0
	fi
	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "$((now - since))" -ge "$need" ] 2>/dev/null; then
		return 1
	fi
	return 0
}

qsc_ps_policy_refresh() {
	local plugged=0 now="${QSC_PS_NOW:-0}"

	QSC_PS_MODE=active
	QSC_PS_DESC_FORCE_STATIC=0

	qsc_ps_apply_profile_defaults
	[ "${QSC_PS_PROFILE:-balanced}" = "aggressive" ] &&
		QSC_PS_DESC_FORCE_STATIC=1

	if type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
		plugged=1
	fi

	# 未插电深睡粘滞：不读亮度，直接再睡
	if [ "$plugged" != "1" ] &&
		[ ! -f "$DATADIR/power_switch" ] &&
		type qsc_ps_policy_try_deep_sticky >/dev/null 2>&1 &&
		qsc_ps_policy_try_deep_sticky; then
		return 0
	fi
	QSC_PS_DEEP_STICKY_N=0

	# 先刷新场景，再分支（停充维持也要息屏信息）
	qsc_ps_policy_scene

	if [ -f "$DATADIR/power_switch" ] && [ ! -f "$MODULE_OFF_FLAG" ]; then
		QSC_PS_MODE=maintain
		qsc_ps_maintain_secs
		if [ "${QSC_PS_SCREEN_OFF:-0}" = "1" ] || [ "${QSC_PS_DEEP:-0}" = "1" ]; then
			QSC_PS_DESC_FORCE_STATIC=1
		fi
		qsc_ps_policy_edge_log
		return 0
	fi

	if [ "$plugged" = "1" ]; then
		QSC_PS_MODE=plugged
		QSC_PS_PARK_EXIT_SINCE=0
		QSC_PS_DEEP_EXIT_HITS=0
		qsc_ps_policy_edge_log
		return 0
	fi

	QSC_PS_MODE=park
	if [ "${QSC_PS_DEEP:-0}" = "1" ]; then
		QSC_PS_MODE=deep
		QSC_PS_IDLE_EFF="${QSC_PS_DEEP_IDLE:-900}"
		QSC_PS_FULL_MAX_GAP="${QSC_PS_DEEP_FULL_GAP:-7200}"
		QSC_PS_HB_SEC="$(qsc_clamp_int "${QSC_PS_HB_SEC:-180}" 180 900 600)"
		QSC_PS_DESC_FORCE_STATIC=1
		QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
		QSC_PS_PARK_EXIT_SINCE=0
		QSC_PS_DEEP_EXIT_HITS=0
		qsc_ps_policy_edge_log
		return 0
	fi

	# 曾在深睡：单次探测非 deep 不够，连续 2 次才允许退出（防亮度闪一下）
	case "${QSC_PS_MODE_WAS:-}" in
		deep)
			QSC_PS_DEEP_EXIT_HITS=$((${QSC_PS_DEEP_EXIT_HITS:-0} + 1))
			if [ "${QSC_PS_DEEP_EXIT_HITS:-0}" -lt 2 ] 2>/dev/null; then
				QSC_PS_MODE=deep
				QSC_PS_DEEP=1
				QSC_PS_SCREEN_OFF=1
				QSC_PS_DESC_FORCE_STATIC=1
				QSC_PS_IDLE_EFF="${QSC_PS_DEEP_IDLE:-900}"
				QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
				qsc_ps_policy_edge_log
				return 0
			fi
			;;
		*)
			QSC_PS_DEEP_EXIT_HITS=0
			;;
	esac

	# 息屏加强：须连续息屏满 screen_off_enter_sec（默认 90s）才切 MODE，
	# 避免口袋亮灭立刻进出；深睡仍按 deep_after_sec（默认 600s）另计。
	if [ "${QSC_PS_SCREEN_OFF:-0}" = "1" ]; then
		_enter="${QSC_PS_SCREEN_OFF_ENTER:-90}"
		_since="${QSC_PS_SCREEN_OFF_SINCE:-0}"
		case "$_enter" in ""|*[!0-9]*) _enter=90 ;; esac
		if [ "$now" -gt 0 ] 2>/dev/null &&
			[ "$_since" -gt 0 ] 2>/dev/null &&
			[ "$((now - _since))" -ge "$_enter" ] 2>/dev/null; then
			QSC_PS_MODE=screen_off
			QSC_PS_IDLE_EFF="$QSC_PS_IDLE"
			qsc_ps_native_ready 2>/dev/null &&
				[ "${QSC_PS_IDLE_NATIVE:-0}" -gt "$QSC_PS_IDLE_EFF" ] 2>/dev/null &&
				QSC_PS_IDLE_EFF="$QSC_PS_IDLE_NATIVE"
			QSC_PS_IDLE_EFF=$((QSC_PS_IDLE_EFF + QSC_PS_IDLE_EFF / 2))
			[ "$QSC_PS_IDLE_EFF" -gt 900 ] 2>/dev/null && QSC_PS_IDLE_EFF=900
			QSC_PS_DESC_FORCE_STATIC=1
			QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
			QSC_PS_PARK_EXIT_SINCE=0
			qsc_ps_policy_edge_log
			return 0
		fi
	fi

	# 将离开息屏加强/深睡：滞回，避免短暂误判亮屏就结算总结
	# idle 仍可按驻停拉长；真亮屏时放开简介，避免打开管理器还卡静态约 90s
	case "${QSC_PS_MODE_WAS:-}" in
		deep|screen_off)
			if qsc_ps_policy_hold_park_exit; then
				QSC_PS_MODE="${QSC_PS_MODE_WAS}"
				if [ "$QSC_PS_MODE" = "deep" ]; then
					QSC_PS_IDLE_EFF="${QSC_PS_DEEP_IDLE:-900}"
				else
					QSC_PS_IDLE_EFF="$QSC_PS_IDLE"
					qsc_ps_native_ready 2>/dev/null &&
						[ "${QSC_PS_IDLE_NATIVE:-0}" -gt "$QSC_PS_IDLE_EFF" ] 2>/dev/null &&
						QSC_PS_IDLE_EFF="$QSC_PS_IDLE_NATIVE"
					QSC_PS_IDLE_EFF=$((QSC_PS_IDLE_EFF + QSC_PS_IDLE_EFF / 2))
					[ "$QSC_PS_IDLE_EFF" -gt 900 ] 2>/dev/null && QSC_PS_IDLE_EFF=900
				fi
				QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
				QSC_PS_SCREEN_CACHE_AT=0
				if type qsc_ps_screen_is_off >/dev/null 2>&1 && ! qsc_ps_screen_is_off; then
					QSC_PS_DESC_FORCE_STATIC=0
					QSC_PS_SCREEN_OFF=0
					QSC_PS_DEEP=0
					if type qsc_ps_desc_worker_wanted >/dev/null 2>&1 &&
						qsc_ps_desc_worker_wanted; then
						type qsc_start_description_worker >/dev/null 2>&1 &&
							qsc_start_description_worker
					fi
				else
					QSC_PS_DESC_FORCE_STATIC=1
					QSC_PS_SCREEN_OFF=1
					[ "$QSC_PS_MODE" = "deep" ] && QSC_PS_DEEP=1
				fi
				qsc_ps_policy_edge_log
				return 0
			fi
			;;
	esac
	QSC_PS_PARK_EXIT_SINCE=0
	QSC_PS_DEEP_EXIT_HITS=0

	qsc_ps_policy_edge_log
	return 0
}

qsc_ps_desc_suppressed() {
	[ "${QSC_PS_DESC_FORCE_STATIC:-0}" = "1" ] && return 0
	[ "${QSC_PS_PROFILE:-balanced}" = "aggressive" ] && return 0
	[ "${QSC_PS_DEEP:-0}" = "1" ] && return 0
	[ "${QSC_PS_SCREEN_OFF:-0}" = "1" ] && [ "${QSC_PS_SCREEN_OFF_SAVER:-0}" = "1" ] && return 0
	return 1
}

# 是否应跑简介 worker（按需）。
# 有 XP：仅 enter 待消费或正在观看时跑；leave/息屏后退出，空闲零进程。
# 无 XP：亮屏且未驻停时允许跑（dumpsys 降级，约数十秒级响应，不过夜常驻）。
qsc_ps_desc_worker_wanted() {
	type qsc_description_enabled >/dev/null 2>&1 || return 1
	qsc_description_enabled || return 1
	[ "${QSC_PS_PROFILE:-balanced}" = "aggressive" ] && return 1

	# —— XP 边沿优先于 deep/park ——
	# 否则主服务被 inotify 叫醒后仍因 MODE=deep 拒启 worker，队列干晾到整段 idle 结束。
	if type qsc_manager_viewer_xp_edge_pending >/dev/null 2>&1 &&
		qsc_manager_viewer_xp_edge_pending; then
		return 0
	fi
	if type qsc_desc_viewing_active >/dev/null 2>&1 &&
		qsc_desc_viewing_active; then
		# 息屏则收掉（亮屏再靠 enter 拉起）；有 pending 上面已 return 0
		if type qsc_ps_screen_is_off >/dev/null 2>&1 &&
			qsc_ps_screen_is_off; then
			type qsc_desc_viewing_clear >/dev/null 2>&1 &&
				qsc_desc_viewing_clear
			return 1
		fi
		return 0
	fi

	case "${QSC_PS_MODE:-}" in
		deep|screen_off)
			# 滞回期已亮屏：仍可走无 XP dumpsys 降级
			if type qsc_ps_screen_is_off >/dev/null 2>&1 &&
				! qsc_ps_screen_is_off; then
				:
			else
				return 1
			fi
			;;
	esac
	[ "${QSC_PS_PARK_ACTIVE:-0}" = "1" ] &&
		type qsc_ps_screen_is_off >/dev/null 2>&1 &&
		qsc_ps_screen_is_off &&
		return 1

	# 无 XP：亮屏降级常驻（息屏/驻停仍停），避免「打开管理器要等好几分钟」
	if type qsc_fg_xp_ready >/dev/null 2>&1 && qsc_fg_xp_ready; then
		return 1
	fi
	if type qsc_ps_screen_is_off >/dev/null 2>&1 && qsc_ps_screen_is_off; then
		return 1
	fi
	return 0
}
