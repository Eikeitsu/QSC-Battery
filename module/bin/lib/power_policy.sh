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

# 运行态（qsc_ps_policy_refresh 填写）
QSC_PS_MODE=active
QSC_PS_SCREEN_OFF=0
QSC_PS_NIGHT=0
QSC_PS_DEEP=0
QSC_PS_DESC_FORCE_STATIC=0
QSC_PS_SCREEN_OFF_SINCE=0
QSC_PS_SCREEN_CACHE_AT=0
QSC_PS_SCREEN_CACHE_VAL=0
QSC_PS_MAINTAIN_EFF=30

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

# 廉价息屏探测；失败视为亮屏。缓存 60s。
qsc_ps_screen_is_off() {
	local now="${QSC_PS_NOW:-0}" p v
	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "$now" = "${QSC_PS_SCREEN_CACHE_AT:-}" ]; then
		[ "${QSC_PS_SCREEN_CACHE_VAL:-0}" = "1" ]
		return $?
	fi
	if [ "$now" -gt 0 ] 2>/dev/null &&
		[ "$((now - ${QSC_PS_SCREEN_CACHE_AT:-0}))" -lt 60 ] 2>/dev/null; then
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

	# 先刷新场景，再分支（停充维持也要息屏信息）
	qsc_ps_policy_scene

	if [ -f "$DATADIR/power_switch" ] && [ ! -f "$MODULE_OFF_FLAG" ]; then
		QSC_PS_MODE=maintain
		qsc_ps_maintain_secs
		if [ "${QSC_PS_SCREEN_OFF:-0}" = "1" ] || [ "${QSC_PS_DEEP:-0}" = "1" ]; then
			QSC_PS_DESC_FORCE_STATIC=1
		fi
		return 0
	fi

	if [ "$plugged" = "1" ]; then
		QSC_PS_MODE=plugged
		# 插电充电中不拉未插电 DeepPark
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
		return 0
	fi

	if [ "${QSC_PS_SCREEN_OFF:-0}" = "1" ]; then
		QSC_PS_MODE=screen_off
		QSC_PS_IDLE_EFF="$QSC_PS_IDLE"
		qsc_ps_native_ready 2>/dev/null &&
			[ "${QSC_PS_IDLE_NATIVE:-0}" -gt "$QSC_PS_IDLE_EFF" ] 2>/dev/null &&
			QSC_PS_IDLE_EFF="$QSC_PS_IDLE_NATIVE"
		QSC_PS_IDLE_EFF=$((QSC_PS_IDLE_EFF + QSC_PS_IDLE_EFF / 2))
		[ "$QSC_PS_IDLE_EFF" -gt 900 ] 2>/dev/null && QSC_PS_IDLE_EFF=900
		QSC_PS_DESC_FORCE_STATIC=1
		QSC_PS_WAIT_FALLBACK="$QSC_PS_IDLE_EFF"
		return 0
	fi

	return 0
}

qsc_ps_desc_suppressed() {
	[ "${QSC_PS_DESC_FORCE_STATIC:-0}" = "1" ] && return 0
	[ "${QSC_PS_PROFILE:-balanced}" = "aggressive" ] && return 0
	[ "${QSC_PS_DEEP:-0}" = "1" ] && return 0
	[ "${QSC_PS_SCREEN_OFF:-0}" = "1" ] && [ "${QSC_PS_SCREEN_OFF_SAVER:-0}" = "1" ] && return 0
	return 1
}
