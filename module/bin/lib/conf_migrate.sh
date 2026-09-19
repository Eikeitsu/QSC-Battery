#!/system/bin/sh
# 拆分配置：避免省电/通知键继续留在 config.conf（双源）。
# 与安装策略对齐：省电间隔 / 档位 / DeepPark 等不从旧 conf 覆盖迁出
# （更新时本就用新版 power.conf 默认）；仅迁出「偏好类」与通知。

# 不迁出、只从 config.conf 删除（留给 power.conf 模板/新版默认）
QSC_POWER_STRIP_ONLY="power_saver power_profile screen_off_saver night_saver deep_idle_enable deep_after_sec deep_idle_sec deep_full_gap_sec heartbeat_sec screen_probe_dumpsys loop_interval_sec loop_interval_maintain_sec loop_interval_idle_sec loop_interval_idle_native_sec loop_interval_plugged_sec loop_interval_plugged_native_sec loop_interval_near_window"

# 与 qsc_merge_side_confs 一致：用户偏好可保留
QSC_POWER_KEEP="native_daemon native_impl description_enable stop_hold_wakelock"

QSC_NOTIFY_KEYS="notify_charge_event notify_charge_kinds notify_power_status"

qsc_conf_file_ensure() {
	local f="$1" header="$2"
	[ -n "$f" ] || return 1
	[ -f "$f" ] && return 0
	mkdir -p "$(dirname "$f")" 2>/dev/null
	printf '%s\n' "$header" >"$f" 2>/dev/null
}

qsc_conf_move_key() {
	local src="$1" dst="$2" key="$3" line
	[ -f "$src" ] && [ -f "$dst" ] || return 1
	line="$(grep -E "^${key}=" "$src" 2>/dev/null | head -n1)"
	[ -n "$line" ] || return 1
	sed -i "/^${key}=/d" "$dst" 2>/dev/null
	printf '%s\n' "$line" >>"$dst" 2>/dev/null
	return 0
}

qsc_conf_strip_keys_from() {
	local file="$1" key
	[ -f "$file" ] || return 0
	shift
	for key in "$@"; do
		sed -i "/^${key}=/d" "$file" 2>/dev/null
	done
}

qsc_conf_migrate_split() {
	local conf="${CONF:-}"
	local power="${POWER_CONF:-}"
	local notify="${NOTIFY_CONF:-}"
	local k migrated=0
	[ -n "$conf" ] && [ -f "$conf" ] || return 0
	[ -n "$power" ] && [ -n "$notify" ] || return 0

	qsc_conf_file_ensure "$power" "# QSC power.conf (migrated)"
	qsc_conf_file_ensure "$notify" "# QSC notify.conf (migrated)"

	# 偏好类：旧主 conf 有则写入 power.conf
	for k in $QSC_POWER_KEEP; do
		if grep -E "^${k}=" "$conf" >/dev/null 2>&1; then
			qsc_conf_move_key "$conf" "$power" "$k" && migrated=1
		fi
	done

	# 通知：保留用户开关与勿扰时段
	for k in $QSC_NOTIFY_KEYS; do
		if grep -E "^${k}=" "$conf" >/dev/null 2>&1; then
			qsc_conf_move_key "$conf" "$notify" "$k" && migrated=1
		fi
	done
	if grep -E '^notify_quiet_schedule=' "$conf" >/dev/null 2>&1; then
		sed -i '/^notify_quiet_schedule=/d' "$notify" 2>/dev/null
		grep -E '^notify_quiet_schedule=' "$conf" >>"$notify" 2>/dev/null && migrated=1
	fi

	# 省电旋钮：只删双源，不覆盖新版 power.conf
	# shellcheck disable=SC2086
	qsc_conf_strip_keys_from "$conf" $QSC_POWER_STRIP_ONLY $QSC_POWER_KEEP night_schedule
	# shellcheck disable=SC2086
	qsc_conf_strip_keys_from "$conf" $QSC_NOTIFY_KEYS notify_quiet_schedule

	[ "$migrated" = "1" ] && type qsc_log >/dev/null 2>&1 &&
		qsc_log info "已整理省电/通知配置（间隔用新版默认，偏好/通知已迁出）"
	return 0
}
