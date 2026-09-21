#!/system/bin/sh
# charge: MCA / preferred / power stop-start-reset
# 实时探测并写入 MCA（不依赖过期 profile；不 chmod）
# 用法：qsc_mca_write stop | qsc_mca_write start
qsc_mca_write() {
	local label="$1"
	local val="" path="" cand
	case "$label" in
		stop) val=1 ;;
		start) val=0 ;;
		*) return 1 ;;
	esac

	# 本启动周期已证实 MCA 停充无效（可写但不控充）→ 跳过
	if [ "$label" = "stop" ] && qsc_mca_skip_stop; then
		return 1
	fi

	qsc_load_device_profile 2>/dev/null || true

	# 未识别为 MCA 的机型不抢先盲扫 handle_state
	# （K60U 等非 MCA 不应走专用路径；有路径残留时仅尝试该路径）
	if [ "${QSC_MCA:-0}" != "1" ]; then
		if ! qsc_mca_node_ok "$QSC_MCA_PATH" 2>/dev/null && \
			{ [ -z "$QSC_MCA_PATH" ] || [ ! -e "$QSC_MCA_PATH" ]; }; then
			return 1
		fi
	fi

	# 1) 已缓存且仍存在的路径优先
	if qsc_mca_node_ok "$QSC_MCA_PATH" 2>/dev/null || { [ -n "$QSC_MCA_PATH" ] && [ -e "$QSC_MCA_PATH" ]; }; then
		if qsc_mca_raw_echo "$QSC_MCA_PATH" "$val"; then
			path="$QSC_MCA_PATH"
		fi
	fi

	# 2) 仅 MCA 机型才做候选/find 盲扫（小米17/K90）
	if [ -z "$path" ] && [ "${QSC_MCA:-0}" = "1" ]; then
		for cand in $QSC_MCA_CANDIDATES $QSC_MCA_STOP_HANDLE_CANDIDATES; do
			qsc_mca_node_ok "$cand" 2>/dev/null || [ -e "$cand" ] || continue
			if qsc_mca_raw_echo "$cand" "$val"; then
				path="$cand"
				break
			fi
		done
	fi

	if [ -z "$path" ] && [ "${QSC_MCA:-0}" = "1" ]; then
		cand="$(qsc_find_mca_path 2>/dev/null)" || cand=""
		if { qsc_mca_node_ok "$cand" 2>/dev/null || [ -e "$cand" ]; } && qsc_mca_raw_echo "$cand" "$val"; then
			path="$cand"
		fi
	fi

	if [ -z "$path" ] && [ "${QSC_MCA:-0}" = "1" ]; then
		for cand in $QSC_MCA_STOP_HANDLE_CANDIDATES; do
			qsc_mca_node_ok "$cand" 2>/dev/null || [ -e "$cand" ] || continue
			if qsc_mca_raw_echo "$cand" "$val"; then
				path="$cand"
				break
			fi
		done
	fi

	if [ -z "$path" ]; then
		if qsc_debug_enabled; then
			qsc_log_once mca_path_missing debug \
				"MCA节点探测失败：profile_mca=$(qsc_profile_get mca 2>/dev/null) profile_path=$(qsc_profile_get mca_path 2>/dev/null)"
		fi
		return 1
	fi

	if qsc_debug_enabled; then
		_mca_readback=""
		qsc_read_node "$path" && _mca_readback="$QSC_NODE_VAL"
		qsc_log_once "mca_write_$label" debug \
			"MCA写入：mode=$label path=$path request=$val readback=${_mca_readback:-?}"
	fi

	if [ "$label" = "stop" ]; then
		# 硬复核：写入成功 ≠ 真停充（K60U 假 MCA / 延迟生效）
		if ! qsc_mca_stop_verify; then
			qsc_mca_mark_ineffective "$path"
			stop_ok=0
			qsc_dbg "MCA stop 复核失败 path=$path，改试其它节点"
			return 1
		fi
		QSC_MCA=1
		QSC_MCA_PATH="$path"
		QSC_MCA_STOP=1
		QSC_MCA_START=0
		if [ "$(qsc_profile_get mca_path 2>/dev/null)" != "$path" ]; then
			qsc_write_device_profile "$path" >/dev/null 2>&1 || true
		fi
		stop_nodes="$path=$val (MCA)"
		log_log=1
		stop_ok=1
		qsc_save_active_switch "${path},start=0,stop=1"
		rm -f "$DATADIR/mca_ineffective" 2>/dev/null
		qsc_log_once_clear mca_ineffective 2>/dev/null || true
		qsc_dbg "MCA stop 成功 path=$path"
	else
		QSC_MCA=1
		QSC_MCA_PATH="$path"
		QSC_MCA_STOP=1
		QSC_MCA_START=0
		if [ "$(qsc_profile_get mca_path 2>/dev/null)" != "$path" ]; then
			qsc_write_device_profile "$path" >/dev/null 2>&1 || true
		fi
		start_node="$path"
		start_val="$val"
		log_log2=1
		start_ok=1
		qsc_dbg "MCA start 成功 path=$path"
	fi
	return 0
}

# 有 preferred_switch 时优先写该节点；MCA 机型仍优先 MCA
qsc_pref_write() {
	local mode="$1"
	local val
	qsc_load_device_profile
	[ -n "$QSC_PREF_PATH" ] && [ -f "$QSC_PREF_PATH" ] || return 1
	if [ "$mode" = "stop" ]; then
		val="$QSC_PREF_STOP"
		[ -n "$val" ] || return 1
		qsc_write_node "$QSC_PREF_PATH" "$val" || return 1
		stop_nodes="$QSC_PREF_PATH=$val (preferred)"
		log_log=1
		stop_ok=1
		qsc_save_active_switch "${QSC_PREF_PATH},start=${QSC_PREF_START},stop=${QSC_PREF_STOP}"
	else
		val="$QSC_PREF_START"
		[ -n "$val" ] || return 1
		qsc_write_node "$QSC_PREF_PATH" "$val" || return 1
		start_node="$QSC_PREF_PATH"
		start_val="$val"
		log_log2=1
		start_ok=1
	fi
	return 0
}

qsc_power_stop() {
	stop_ok=0
	stop_nodes=""
	local _batch _vd
	qsc_load_device_profile 2>/dev/null || true
	_batch="${QSCV_switch_batch_blind:-}"
	[ -n "$_batch" ] ||
		_batch="$(echo "${config_conf:-}" | egrep '^switch_batch_blind=' | sed -n 's/switch_batch_blind=//g;$p')"
	_batch="$(qsc_clamp_int "${_batch:-1}" 0 1 1)"
	qsc_dbg "power_stop 开始 batch=$_batch mca=${QSC_MCA:-?} mca_path=${QSC_MCA_PATH:-?} skip_mca=$([ -f "$DATADIR/mca_ineffective" ] && echo 1 || echo 0)"
	# MCA 最先：直接 echo 1，不走全量列表（小米17/K90）；K60U 等非 MCA 不会进此路径
	if qsc_mca_write stop; then
		qsc_dbg "power_stop：MCA 路径成功 [$stop_nodes]"
		return
	fi
	if qsc_pref_write stop; then
		# preferred：测开关认定有效；仍用电流软确认，失败则继续试列表
		_vd="$(echo "${config_conf:-}" | egrep '^switch_verify_sec=' | sed -n 's/switch_verify_sec=//g;$p')"
		_vd="$(qsc_clamp_int "${_vd:-1}" 0 5 1)"
		[ "$_vd" -gt 0 ] 2>/dev/null && sleep "$_vd"
		if qsc_charge_looks_stopped; then
			qsc_dbg "power_stop：preferred 成功且电流已停 [$stop_nodes]"
			return
		fi
		qsc_dbg "power_stop：preferred 写入后电流仍高，继续试列表"
		stop_ok=0
		stop_nodes=""
		qsc_clear_active_switch
	fi
	if [ -n "$QSC_USER_SWITCHES" ]; then
		# 用户显式配置：写入后校验（允许策略类节点）
		qsc_write_switch_list stop "$QSC_USER_SWITCHES" verify 1
		if [ "$stop_ok" = "1" ]; then
			stop_nodes="$stop_nodes (user)"
			qsc_dbg "power_stop：用户开关成功 [$stop_nodes]"
			return
		fi
	fi
	if [ "$_batch" = "1" ]; then
		# 全量盲写（小米等需多节点同时压住）；非 MCA 再做电流复核
		qsc_write_switch_list stop "$switch_list"
		if [ "$stop_ok" = "1" ] && ! qsc_device_is_mca; then
			_vd="$(echo "${config_conf:-}" | egrep '^switch_verify_sec=' | sed -n 's/switch_verify_sec=//g;$p')"
			_vd="$(qsc_clamp_int "${_vd:-1}" 0 5 1)"
			[ "$_vd" -gt 0 ] 2>/dev/null && sleep "$_vd"
			if ! qsc_charge_looks_stopped; then
				qsc_log_once batch_fake warn \
					"盲写后电流仍高（通用节点机型），改逐节点校验"
				qsc_dbg "power_stop：盲写假成功，回退 verify"
				stop_ok=0
				stop_nodes=""
				qsc_clear_active_switch
				qsc_write_switch_list stop "$switch_list" verify
			fi
		fi
	else
		# 对齐 0814/K60U：逐节点写入后电流校验，无效则回滚并试下一条
		qsc_write_switch_list stop "$switch_list" verify
	fi
	if [ "$stop_ok" = "1" ]; then
		qsc_dbg "power_stop：列表成功 batch=$_batch [$stop_nodes]"
		return
	fi
	# 末位兜底：电流墙 / 端口 suspend（仍做校验，避免误伤快充协商）
	qsc_write_switch_list stop "$QSC_LAST_RESORT_SWITCHES" verify
	qsc_dbg "power_stop：末位兜底 stop_ok=$stop_ok [$stop_nodes]"
}

qsc_power_start() {
	start_ok=0
	start_node=""
	start_val=""
	if qsc_mca_write start; then
		qsc_clear_active_switch
		qsc_stop_wakelock_release
		return
	fi
	if qsc_pref_write start; then
		qsc_clear_active_switch
		qsc_stop_wakelock_release
		return
	fi
	if [ -n "$QSC_USER_SWITCHES" ]; then
		qsc_write_switch_list start "$QSC_USER_SWITCHES" "" 1
		if [ "$start_ok" = "1" ]; then
			qsc_clear_active_switch
			qsc_stop_wakelock_release
			return
		fi
	fi
	if [ -f "$DATADIR/active_switch" ]; then
		_as="$(cat "$DATADIR/active_switch" 2>/dev/null | tr -d ' \r\n')"
		_ar="$(echo "$_as" | sed -n 's/,start=.*//g;$p')"
		_av="$(echo "$_as" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
		if [ -n "$_ar" ] && [ -f "$_ar" ] && [ -n "$_av" ]; then
			# MCA 节点不用 chmod
			case "$_ar" in
				*handle_state*|*stop_handle_charge*)
					_ok=0
					qsc_mca_raw_echo "$_ar" "$_av" && _ok=1
					;;
				*)
					_ok=0
					qsc_write_node "$_ar" "$_av" && _ok=1
					;;
			esac
			if [ "$_ok" = "1" ]; then
				start_node="$_ar"
				start_val="$_av"
				log_log2=1
				start_ok=1
				qsc_clear_active_switch
				qsc_stop_wakelock_release
				return
			fi
		fi
	fi
	qsc_write_switch_list start "$switch_list"
	if [ "$start_ok" != "1" ]; then
		qsc_write_switch_list start "$QSC_LAST_RESORT_SWITCHES"
	fi
	qsc_clear_active_switch
	qsc_stop_wakelock_release
}

qsc_power_reset() {
	sleep 2
	qsc_power_stop
	sleep 1
	qsc_power_start
}

# 停充成功后多久之内不下「拔线」结论（秒）
QSC_UNPLUG_COOLDOWN=90

# 充电器是不是真被拔了。
#
# 不能只看 online 掉 0 或 status 不是 Charging：本模块的停充手段里就有端口
# suspend 与电流墙，写下去之后 usb/online 会变 0、status 也可能变成
# Discharging，看起来和拔线一模一样。据此还原节点就会在阈值处反复启停
# （电量到 100% 停充，下一轮误判成拔线又还原，于是立刻重新充电）。
#
# 所以这里只认「线还插着」的正面证据，任何一条成立就判定没拔：
#   1) present 且有 VBUS/类型旁证（孤立 present 在 K90U 未插电也会粘住）
#   2) type / VBUS 电压等物理存在信号
#   3) 距上次停充不足 QSC_UNPLUG_COOLDOWN 秒（停充瞬间信号会抖；
#      冷却期内也允许单信 present 顶住）
# 不再单信 status=Not charging（K90U 未插电待机也报这个）。
