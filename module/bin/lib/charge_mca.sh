#!/system/bin/sh
# charge: MCA / preferred / power stop-start-reset
# 停充写入语义对齐 v2026.08.14：写成功即认；仅 MCA=1 走专用路径。
# 用法：qsc_mca_write stop | qsc_mca_write start
qsc_mca_write() {
	local label="$1"
	local val="" path="" cand
	case "$label" in
		stop) val=1 ;;
		start) val=0 ;;
		*) return 1 ;;
	esac

	qsc_load_device_profile 2>/dev/null || true

	# 对齐 0814：未标 MCA=1 不走专用路径（不盲扫 handle_state）
	[ "${QSC_MCA:-0}" = "1" ] || return 1

	# 硬复核曾判定无效：仅 switch_hard_verify=1 时跳过
	if [ "$label" = "stop" ] && qsc_switch_hard_verify_on && qsc_mca_skip_stop; then
		qsc_dbg "跳过 MCA（mca_ineffective）"
		return 1
	fi

	# 1) 已缓存且仍存在的路径优先
	if qsc_mca_node_ok "$QSC_MCA_PATH" 2>/dev/null || { [ -n "$QSC_MCA_PATH" ] && [ -e "$QSC_MCA_PATH" ]; }; then
		if qsc_mca_raw_echo "$QSC_MCA_PATH" "$val"; then
			path="$QSC_MCA_PATH"
		fi
	fi

	# 2) 候选 / find（仅 MCA=1）
	if [ -z "$path" ]; then
		for cand in $QSC_MCA_CANDIDATES $QSC_MCA_STOP_HANDLE_CANDIDATES; do
			qsc_mca_node_ok "$cand" 2>/dev/null || [ -e "$cand" ] || continue
			if qsc_mca_raw_echo "$cand" "$val"; then
				path="$cand"
				break
			fi
		done
	fi

	if [ -z "$path" ]; then
		cand="$(qsc_find_mca_path 2>/dev/null)" || cand=""
		if { qsc_mca_node_ok "$cand" 2>/dev/null || [ -e "$cand" ]; } && qsc_mca_raw_echo "$cand" "$val"; then
			path="$cand"
		fi
	fi

	if [ -z "$path" ]; then
		qsc_dbg "MCA节点探测失败：profile_mca=$(qsc_profile_get mca 2>/dev/null) profile_path=$(qsc_profile_get mca_path 2>/dev/null)"
		return 1
	fi

	if qsc_debug_enabled; then
		_mca_readback=""
		qsc_read_node "$path" && _mca_readback="$QSC_NODE_VAL"
		qsc_dbg "MCA写入：mode=$label path=$path request=$val readback=${_mca_readback:-?}"
	fi

	QSC_MCA=1
	QSC_MCA_PATH="$path"
	QSC_MCA_STOP=1
	QSC_MCA_START=0
	if [ "$(qsc_profile_get mca_path 2>/dev/null)" != "$path" ]; then
		qsc_write_device_profile "$path" >/dev/null 2>&1 || true
	fi
	if [ "$label" = "stop" ]; then
		# 默认写成功即认；switch_hard_verify=1 时事后电流复核，失败则拉黑并改试列表
		if qsc_switch_hard_verify_on; then
			if ! qsc_mca_stop_verify; then
				qsc_mca_mark_ineffective "$path"
				stop_ok=0
				qsc_dbg "MCA 硬复核失败 path=$path"
				return 1
			fi
			rm -f "$DATADIR/mca_ineffective" 2>/dev/null
			qsc_log_once_clear mca_ineffective 2>/dev/null || true
		elif qsc_debug_enabled && ! qsc_charge_looks_stopped; then
			qsc_dbg "MCA 写入后瞬时仍像在充（hard_verify 关，不回滚）"
		fi
		stop_nodes="$path=$val (MCA)"
		log_log=1
		stop_ok=1
		qsc_save_active_switch "${path},start=0,stop=1"
		qsc_dbg "MCA stop 成功 path=$path"
	else
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
	local _batch
	qsc_load_device_profile 2>/dev/null || true
	_batch="${QSCV_switch_batch_blind:-}"
	[ -n "$_batch" ] ||
		_batch="$(echo "${config_conf:-}" | egrep '^switch_batch_blind=' | sed -n 's/switch_batch_blind=//g;$p')"
	_batch="$(qsc_clamp_int "${_batch:-1}" 0 1 1)"
	qsc_dbg "power_stop 开始 batch=$_batch mca=${QSC_MCA:-?} mca_path=${QSC_MCA_PATH:-?}"
	# MCA 最先（仅 MCA=1）；对齐 0814 写成功即返回
	if qsc_mca_write stop; then
		qsc_dbg "power_stop：MCA 路径成功 [$stop_nodes]"
		return
	fi
	if qsc_pref_write stop; then
		qsc_dbg "power_stop：preferred 成功 [$stop_nodes]"
		return
	fi
	if [ -n "$QSC_USER_SWITCHES" ]; then
		# 用户显式配置：写入成功即认（允许策略类节点）
		qsc_write_switch_list stop "$QSC_USER_SWITCHES" first 1
		if [ "$stop_ok" = "1" ]; then
			stop_nodes="$stop_nodes (user)"
			qsc_dbg "power_stop：用户开关成功 [$stop_nodes]"
			return
		fi
	fi
	if [ "$_batch" = "1" ]; then
		# 对齐 0814 / 现行默认：全量盲写，写成功即认（瞬时大电流不硬回滚）
		qsc_write_switch_list stop "$switch_list"
		if [ "$stop_ok" = "1" ] && qsc_debug_enabled; then
			if type qsc_charge_looks_stopped >/dev/null 2>&1 && ! qsc_charge_looks_stopped; then
				qsc_dbg "盲写已认停充，瞬时电流仍高（对齐0814不回滚）"
			fi
		fi
	else
		# 可选：逐节点电流校验（非 0814 默认；用户关盲写时启用）
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
