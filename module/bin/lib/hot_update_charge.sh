#!/system/bin/sh
# 热更新充电自愈：杀服务前尽量还原节点；新服务启动再强制扫一轮孤儿/简介。
# 由 hot_update.sh 加载；hotinstall / txn worker 在 pkill 之后调用。

qsc_hot_mark_charge_dirty() {
	local root="${1:-}"
	[ -n "$root" ] && [ -d "$root" ] || return 1
	mkdir -p "$root/data" 2>/dev/null
	touch "$root/data/hot_update_charge_dirty" 2>/dev/null
	# 强制新服务首轮再跑孤儿检查（即使本函数已尝试还原）
	rm -f "$root/data/.orphan_checked" 2>/dev/null
	return 0
}

# 在已 source common 的环境中：有停充标记或节点卡在停充值时还原。
# 热更新场景优先保证「能充电」；停充策略由新服务按电量重新评估。
qsc_hot_restore_charge_nodes() {
	local need=0
	type qsc_build_switch_list >/dev/null 2>&1 || return 1
	type qsc_power_start >/dev/null 2>&1 || return 1
	qsc_build_switch_list
	[ -f "$DATADIR/power_switch" ] && need=1
	if [ "$need" = "1" ]; then
		qsc_power_start
		if [ "${start_ok:-0}" = "1" ]; then
			rm -f "$DATADIR/power_switch" "$DATADIR/temp_switch" \
				"$DATADIR/battery_switch" "$DATADIR/app_stop_flag" \
				"$DATADIR/resume_fail_hint" 2>/dev/null
			type qsc_clear_active_switch >/dev/null 2>&1 && qsc_clear_active_switch
			type qsc_stop_wakelock_release >/dev/null 2>&1 && qsc_stop_wakelock_release
			type qsc_log >/dev/null 2>&1 &&
				qsc_log info "热更新：已还原充电节点并清除停充标记 [$start_node <- $start_val]"
			return 0
		fi
		touch "$DATADIR/resume_fail_hint" 2>/dev/null
		type qsc_log >/dev/null 2>&1 &&
			qsc_log error "热更新：还原充电节点失败，已标记 dirty 供新服务重试"
		return 1
	fi
	if type qsc_orphan_stop_check >/dev/null 2>&1; then
		qsc_orphan_stop_check || true
	fi
	return 0
}

# 杀旧进程后、覆盖/拉起新服务前调用。独立子 shell，避免污染调用方。
qsc_hot_prestop_safeguard() {
	local root="$1" rc=0
	[ -n "$root" ] && [ -d "$root/bin" ] || return 0
	qsc_hot_mark_charge_dirty "$root" || true
	(
		MODDIR="$root"
		MODPATH="$root"
		unset QSC_LIBS_LOADED
		# shellcheck disable=SC1090
		. "$root/bin/common.sh" 2>/dev/null || exit 0
		# common → charge.sh 会加载本文件；若旧包尚无则再 source 一次
		if ! type qsc_hot_restore_charge_nodes >/dev/null 2>&1; then
			[ -f "$LIBDIR/hot_update_charge.sh" ] &&
				. "$LIBDIR/hot_update_charge.sh" 2>/dev/null || exit 0
		fi
		qsc_hot_restore_charge_nodes
		exit $?
	)
	rc=$?
	return "$rc"
}

# 新 service 首轮：处理 dirty、强制孤儿检查、刷简介并唤醒 viewer。
qsc_hot_boot_charge_heal() {
	local dirty=0
	[ -f "$DATADIR/hot_update_charge_dirty" ] && dirty=1
	[ -f "$DATADIR/hot_update_at" ] && dirty=1
	[ "$dirty" = "1" ] || return 0

	type qsc_build_switch_list >/dev/null 2>&1 && qsc_build_switch_list
	# 仍带着停充标记：热更新前还原失败或杀进程后再次被写上——优先清掉以便能充
	if [ -f "$DATADIR/power_switch" ] && type qsc_power_start >/dev/null 2>&1; then
		qsc_power_start
		if [ "${start_ok:-0}" = "1" ]; then
			rm -f "$DATADIR/power_switch" "$DATADIR/temp_switch" \
				"$DATADIR/battery_switch" "$DATADIR/app_stop_flag" \
				"$DATADIR/resume_fail_hint" 2>/dev/null
			type qsc_clear_active_switch >/dev/null 2>&1 && qsc_clear_active_switch
			type qsc_stop_wakelock_release >/dev/null 2>&1 && qsc_stop_wakelock_release
			type qsc_log >/dev/null 2>&1 &&
				qsc_log info "热更新启动自愈：已还原停充节点 [$start_node <- $start_val]"
		else
			touch "$DATADIR/resume_fail_hint" 2>/dev/null
			type qsc_log >/dev/null 2>&1 &&
				qsc_log error "热更新启动自愈：还原失败，将持续重试"
		fi
	fi
	rm -f "$DATADIR/.orphan_checked" 2>/dev/null
	if type qsc_orphan_stop_check >/dev/null 2>&1; then
		touch "$DATADIR/.orphan_checked" 2>/dev/null
		qsc_orphan_stop_check || true
	fi

	# 简介：强制写一版，并补发 viewer enter（XP 边沿可能在空窗过期）
	if type qsc_description_enabled >/dev/null 2>&1 && qsc_description_enabled; then
		QSC_PS_DESC_FORCE=1
		QSC_PS_DESC_MIN_GAP=0
		if type qsc_ps_load_conf >/dev/null 2>&1; then
			qsc_ps_load_conf 2>/dev/null
			qsc_ps_now 2>/dev/null
			type qsc_ps_policy_refresh >/dev/null 2>&1 && qsc_ps_policy_refresh
			type qsc_ps_refresh_desc >/dev/null 2>&1 &&
				qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
		elif type qsc_refresh_module_description >/dev/null 2>&1; then
			qsc_refresh_module_description
		fi
		QSC_PS_DESC_FORCE=0
		_now_ms="$(date +%s 2>/dev/null || echo 0)"
		if type qsc_xp_write_bus >/dev/null 2>&1; then
			qsc_xp_write_bus /data/system/qsc_xp_viewer \
				"$(printf '%s\tenter\thot_update\n' "$_now_ms")"
		else
			printf '%s\tenter\thot_update\n' "$_now_ms" \
				>/data/system/qsc_xp_viewer 2>/dev/null || true
			chmod 0666 /data/system/qsc_xp_viewer 2>/dev/null || true
		fi
	fi
	rm -f "$DATADIR/hot_update_charge_dirty" 2>/dev/null
	return 0
}
