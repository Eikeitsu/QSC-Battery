#!/system/bin/sh
# install helpers
qsc_abort() {
	ui_print "! $1"
	rm -f /data/adb/qsc/install_auto 2>/dev/null
	if command -v abort >/dev/null 2>&1; then
		abort "$1"
	fi
	exit 1
}
qsc_conf_value() {
	local file="$1"
	local key="$2"
	local count value
	count="$(grep -c "^${key}=" "$file" 2>/dev/null)"
	[ "$count" = "1" ] || return 1
	value="$(sed -n "s/^${key}=//p" "$file" | tr -d ' \r\n')"
	case "$value" in ""|*[!0-9]*) return 1 ;; esac
	echo "$value"
}

# 允许 0/1/auto 等简短标记（非纯数字）
qsc_conf_token() {
	local file="$1"
	local key="$2"
	local count value
	count="$(grep -c "^${key}=" "$file" 2>/dev/null)"
	[ "$count" = "1" ] || return 1
	value="$(sed -n "s/^${key}=//p" "$file" | tr -d ' \r\n')"
	case "$value" in
		""|*[!0-9A-Za-z._:-]*) return 1 ;;
	esac
	echo "$value"
}

qsc_merge_config() {
	local source="$1"
	local target="$2"
	local merged="${target}.merge.$$"
	local default_power_stop default_power_start default_power_stop_time
	local default_charge_full default_power_reset default_compatibility_mode
	local default_temperature_switch
	local default_temperature_stop default_temperature_start
	local default_stop_hold default_notify
	local power_stop power_start power_stop_time charge_full power_reset
	local Compatibility_mode
	local temperature_switch temperature_stop temperature_start
	local stop_hold_wakelock notify_charge_event notify_kinds value _kinds

	default_power_stop="$(qsc_conf_value "$target" power_stop)" || return 1
	default_power_start="$(qsc_conf_value "$target" power_start)" || return 1
	default_power_stop_time="$(qsc_conf_value "$target" power_stop_time)" || return 1
	default_charge_full="$(qsc_conf_value "$target" charge_full)" || return 1
	default_power_reset="$(qsc_conf_value "$target" power_reset)" || return 1
	default_compatibility_mode="$(qsc_conf_value "$target" Compatibility_mode)" || default_compatibility_mode=0
	default_temperature_switch="$(qsc_conf_value "$target" temperature_switch)" || return 1
	default_temperature_stop="$(qsc_conf_value "$target" temperature_switch_stop)" || return 1
	default_temperature_start="$(qsc_conf_value "$target" temperature_switch_start)" || return 1
	default_stop_hold="$(qsc_conf_token "$target" stop_hold_wakelock)" || default_stop_hold=auto
	default_notify="$(qsc_conf_value "$target" notify_charge_event)" || default_notify=0
	notify_kinds="$(sed -n 's/^notify_charge_kinds=//p' "$target" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	[ -n "$notify_kinds" ] || notify_kinds="stop,resume,fail"

	power_stop="$default_power_stop"
	power_start="$default_power_start"
	power_stop_time="$default_power_stop_time"
	charge_full="$default_charge_full"
	power_reset="$default_power_reset"
	Compatibility_mode="$default_compatibility_mode"
	temperature_switch="$default_temperature_switch"
	temperature_stop="$default_temperature_stop"
	temperature_start="$default_temperature_start"
	stop_hold_wakelock="$default_stop_hold"
	notify_charge_event="$default_notify"

	value="$(qsc_conf_value "$source" power_stop)" && [ "$value" -ge 1 -a "$value" -le 110 ] && power_stop="$value"
	value="$(qsc_conf_value "$source" power_start)" && [ "$value" -ge 0 -a "$value" -le 109 ] && power_start="$value"
	value="$(qsc_conf_value "$source" power_stop_time)" && [ "$value" -ge 1 -a "$value" -le 3600 ] && power_stop_time="$value"
	value="$(qsc_conf_value "$source" charge_full)" && [ "$value" -le 1 ] && charge_full="$value"
	value="$(qsc_conf_value "$source" power_reset)" && [ "$value" -le 1 ] && power_reset="$value"
	value="$(qsc_conf_value "$source" Compatibility_mode)" && [ "$value" -le 1 ] && Compatibility_mode="$value"
	value="$(qsc_conf_value "$source" temperature_switch)" && [ "$value" -le 1 ] && temperature_switch="$value"
	value="$(qsc_conf_value "$source" temperature_switch_stop)" && [ "$value" -le 100 ] && temperature_stop="$value"
	value="$(qsc_conf_value "$source" temperature_switch_start)" && [ "$value" -le 100 ] && temperature_start="$value"
	value="$(qsc_conf_token "$source" stop_hold_wakelock)" && case "$value" in 0|1|auto) stop_hold_wakelock="$value" ;; esac
	value="$(qsc_conf_value "$source" notify_charge_event)" && [ "$value" -le 1 ] && notify_charge_event="$value"
	# notify_charge_kinds 允许逗号列表
	_kinds="$(sed -n 's/^notify_charge_kinds=//p' "$source" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	case "$_kinds" in
		""|*[^a-z,]*) ;;
		*)
			notify_kinds="$_kinds"
			;;
	esac

	if [ "$power_stop" != "110" ] && [ "$power_stop" -le "$power_start" ]; then
		power_stop="$default_power_stop"
		power_start="$default_power_start"
		ui_print "- 旧版电量阈值关系无效，已保留新版默认值"
	fi
	if [ "$temperature_stop" -le "$temperature_start" ]; then
		temperature_stop="$default_temperature_stop"
		temperature_start="$default_temperature_start"
		ui_print "- 旧版温控阈值关系无效，已保留新版默认值"
	fi

	cp -f "$target" "$merged" 2>/dev/null || return 1
	sed -i \
		-e "s/^power_stop=.*/power_stop=$power_stop/" \
		-e "s/^power_start=.*/power_start=$power_start/" \
		-e "s/^power_stop_time=.*/power_stop_time=$power_stop_time/" \
		-e "s/^charge_full=.*/charge_full=$charge_full/" \
		-e "s/^power_reset=.*/power_reset=$power_reset/" \
		-e "s/^Compatibility_mode=.*/Compatibility_mode=$Compatibility_mode/" \
		-e "s/^stop_hold_wakelock=.*/stop_hold_wakelock=$stop_hold_wakelock/" \
		-e "s/^notify_charge_event=.*/notify_charge_event=$notify_charge_event/" \
		-e "s/^notify_charge_kinds=.*/notify_charge_kinds=$notify_kinds/" \
		-e "s/^temperature_switch=.*/temperature_switch=$temperature_switch/" \
		-e "s/^temperature_switch_stop=.*/temperature_switch_stop=$temperature_stop/" \
		-e "s/^temperature_switch_start=.*/temperature_switch_start=$temperature_start/" \
		"$merged" || {
		rm -f "$merged"
		return 1
	}

	# —— 保留更新策略 ——
	# 核心策略：从旧配置迁入（停充阈值、通知、无线、App、历史开关等）
	# 运行/省电旋钮：一律留新版模板默认，避免旧间隔把本版省电优化盖掉
	# （power_saver、loop_interval_*、switch_verify_sec 不在此列表）
	_core_migrated=0
	for _nk in wireless_policy history_enable history_interval_sec \
		app_stop app_stop_list native_daemon native_impl chart_show \
		notify_power_status switch_batch_blind unplug_restore \
		charge_full_mode charge_full_wait_sec; do
		_nv="$(sed -n "s/^${_nk}=//p" "$source" 2>/dev/null | head -n1 | tr -d '\r')"
		[ -n "$_nv" ] || continue
		case "$_nk" in
			wireless_policy)
				case "$_nv" in same|ignore) ;; *) continue ;; esac
				;;
			history_enable|app_stop|native_daemon|chart_show|notify_power_status|switch_batch_blind|unplug_restore)
				case "$_nv" in 0|1) ;; *) continue ;; esac
				;;
			charge_full_mode)
				case "$_nv" in current|time|auto) ;; *) continue ;; esac
				;;
			charge_full_wait_sec)
				case "$_nv" in ""|*[!0-9]*) continue ;; esac
				[ "$_nv" -ge 60 ] 2>/dev/null && [ "$_nv" -le 3600 ] 2>/dev/null || continue
				;;
			history_interval_sec)
				case "$_nv" in ""|*[!0-9]*) continue ;; esac
				[ "$_nv" -ge 15 ] 2>/dev/null && [ "$_nv" -le 600 ] 2>/dev/null || continue
				;;
			native_impl)
				case "$_nv" in rust|c|off) ;; *) continue ;; esac
				;;
			app_stop_list)
				# 包名列表：过长或含非法字符则跳过，避免写坏 conf
				case "$_nv" in *[!A-Za-z0-9._,]* ) continue ;; esac
				;;
		esac
		if grep -q "^${_nk}=" "$merged" 2>/dev/null; then
			sed -i "s|^${_nk}=.*|${_nk}=${_nv}|" "$merged"
		else
			echo "${_nk}=${_nv}" >>"$merged"
		fi
		_core_migrated=$((_core_migrated + 1))
	done

	# 明示：省电相关键保持新版（读模板值仅用于提示）
	_idle_n="$(sed -n 's/^loop_interval_idle_native_sec=//p' "$merged" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	_idle="$(sed -n 's/^loop_interval_idle_sec=//p' "$merged" 2>/dev/null | head -n1 | tr -d ' \r\n')"
	ui_print "- 核心停充/通知等配置已保留；省电间隔已用新版默认（idle=${_idle:-?}s native=${_idle_n:-?}s）"
	[ "$_core_migrated" -gt 0 ] && ui_print "- 另迁移 ${_core_migrated} 项运行偏好（无线/历史/守护选型等）"

	# 迁移用户自定义供电开关与停充时段（多行）；跳过策略类节点以免闪充
	sed -i -e '/^power_switch=/d' -e '/^power_stop_schedule=/d' -e '/^notify_quiet_schedule=/d' "$merged" 2>/dev/null
	if grep -q '^power_switch=' "$source" 2>/dev/null; then
		kept_ps=0
		skip_ps=0
		while IFS= read -r _ps_line || [ -n "$_ps_line" ]; do
			[ -n "$_ps_line" ] || continue
			case "$_ps_line" in
				*night_charging*|*cool_mode*|*batt_protect*|*smart_charging*|*adapter_cc_mode*|*step_charging*|*restrict_chg*|*restricted_charging*|*charge_control_*)
					skip_ps=$((skip_ps + 1))
					continue
					;;
			esac
			echo "$_ps_line" >>"$merged"
			kept_ps=$((kept_ps + 1))
		done <<EOF
$(grep '^power_switch=' "$source" 2>/dev/null)
EOF
		if [ "$kept_ps" -gt 0 ]; then
			ui_print "- 已迁移自定义 power_switch（${kept_ps} 条）"
		fi
		if [ "$skip_ps" -gt 0 ]; then
			ui_print "- 已跳过 ${skip_ps} 条策略类 power_switch（易导致闪充）"
		fi
	fi
	if grep -q '^power_stop_schedule=' "$source" 2>/dev/null; then
		grep '^power_stop_schedule=' "$source" >>"$merged" 2>/dev/null
		ui_print "- 已迁移停充时段 power_stop_schedule"
	fi
	if grep -q '^notify_quiet_schedule=' "$source" 2>/dev/null; then
		grep '^notify_quiet_schedule=' "$source" >>"$merged" 2>/dev/null
		ui_print "- 已迁移通知勿扰时段"
	fi
	mv -f "$merged" "$target"
}
