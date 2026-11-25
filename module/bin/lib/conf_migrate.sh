#!/system/bin/sh
# 拆分配置：避免省电/通知键继续留在 config.conf（双源）。
# 与安装策略对齐：省电间隔 / 档位 / DeepPark 等不从旧 conf 覆盖迁出
# （更新时本就用新版 power.conf 默认）；仅迁出「偏好类」与通知。

# 不迁出、只从 config.conf 删除（留给 power.conf 模板/新版默认）
QSC_POWER_STRIP_ONLY="power_saver power_profile screen_off_saver night_saver deep_idle_enable deep_after_sec deep_idle_sec deep_full_gap_sec heartbeat_sec screen_probe_dumpsys loop_interval_sec loop_interval_maintain_sec loop_interval_idle_sec loop_interval_idle_native_sec loop_interval_plugged_sec loop_interval_plugged_native_sec loop_interval_near_window"

# 与 qsc_merge_side_confs 一致：用户偏好可保留
QSC_POWER_KEEP="native_daemon native_impl description_enable stop_hold_wakelock"

QSC_NOTIFY_KEYS="notify_charge_event notify_charge_kinds notify_power_status low_batt_warn low_batt_shutdown low_batt_shutdown_delay_sec low_batt_shutdown_min_uptime_sec low_batt_temp_shutdown"

qsc_conf_file_ensure() {
	local f="$1" header="$2"
	[ -n "$f" ] || return 1
	[ -f "$f" ] && return 0
	mkdir -p "$(dirname "$f")" 2>/dev/null
	printf '%s\n' "$header" >"$f" 2>/dev/null
}

# Magisk overlay + sed -i 偶发把 conf 写成「大段 NUL + 尾部文本」。
# 启动时剥掉 NUL、去掉空行，原子写回，避免读配置失败/行为异常。
qsc_conf_heal_nul_file() {
	local f="$1" tmp sz1 sz2
	[ -n "$f" ] && [ -f "$f" ] || return 0
	sz1="$(wc -c <"$f" 2>/dev/null | tr -d ' ')"
	sz2="$(tr -d '\000' <"$f" 2>/dev/null | wc -c | tr -d ' ')"
	case "$sz1" in ""|*[!0-9]*) return 0 ;; esac
	case "$sz2" in ""|*[!0-9]*) return 0 ;; esac
	[ "$sz1" -eq "$sz2" ] 2>/dev/null && return 0
	tmp="${f}.heal.$$"
	# 仍须像 conf：至少有一行 key=
	if ! tr -d '\000' <"$f" 2>/dev/null | grep -E '^[A-Za-z0-9_]+=.' >/dev/null 2>&1; then
		rm -f "$tmp" 2>/dev/null
		type qsc_log >/dev/null 2>&1 &&
			qsc_log warn "配置文件含 NUL 且修复后无有效键，已跳过：$f"
		return 1
	fi
	tr -d '\000' <"$f" 2>/dev/null | sed '/^$/d' >"$tmp" 2>/dev/null || {
		rm -f "$tmp" 2>/dev/null
		return 1
	}
	mv -f "$tmp" "$f" 2>/dev/null || {
		rm -f "$tmp" 2>/dev/null
		return 1
	}
	type qsc_log >/dev/null 2>&1 &&
		qsc_log warn "已修复含 NUL 的配置文件：$f（多为 sed -i 在模块目录写坏）"
	return 0
}

qsc_conf_heal_all() {
	local f
	# key=value 文本 conf；JSON（current.json）不走此路径
	for f in "${CONF:-}" "${POWER_CONF:-}" "${NOTIFY_CONF:-}" "${DEVICE_PROFILE:-}"; do
		[ -n "$f" ] && [ -f "$f" ] || continue
		qsc_conf_heal_nul_file "$f"
	done
}

# 原子改写 conf 单键（避免 Magisk 目录上 sed -i 打出稀疏/NUL 文件）
qsc_conf_set_key_atomic() {
	local file="$1" key="$2" val="$3" tmp
	[ -n "$file" ] && [ -n "$key" ] || return 1
	mkdir -p "$(dirname "$file")" 2>/dev/null
	[ -f "$file" ] || printf '# QSC conf\n' >"$file" 2>/dev/null
	tmp="${file}.set.$$"
	awk -v k="$key" -v v="$val" '
		BEGIN { done=0 }
		{
			if (!done && index($0, k "=") == 1) {
				print k "=" v
				done=1
			} else print
		}
		END { if (!done) print k "=" v }
	' "$file" >"$tmp" || {
		rm -f "$tmp"
		return 1
	}
	mv -f "$tmp" "$file"
}

# 原子删除单个 key= 行（含多行同键）
qsc_conf_delete_key_atomic() {
	local file="$1" key="$2" tmp
	[ -n "$file" ] && [ -n "$key" ] && [ -f "$file" ] || return 0
	tmp="${file}.rm.$$"
	awk -v k="$key" 'index($0, k "=") != 1 { print }' "$file" >"$tmp" || {
		rm -f "$tmp"
		return 1
	}
	mv -f "$tmp" "$file"
}

# 一次 awk 删多个键，避免循环 sed -i
qsc_conf_delete_keys_atomic() {
	local file="$1" tmp
	[ -f "$file" ] || return 0
	shift
	[ "$#" -gt 0 ] || return 0
	tmp="${file}.rm.$$"
	awk -v keys="$*" '
		BEGIN {
			n = split(keys, a, " ")
			for (i = 1; i <= n; i++) if (a[i] != "") del[a[i]] = 1
		}
		{
			eq = index($0, "=")
			if (eq <= 1) { print; next }
			k = substr($0, 1, eq - 1)
			if (!(k in del)) print
		}
	' "$file" >"$tmp" || {
		rm -f "$tmp"
		return 1
	}
	mv -f "$tmp" "$file"
}

qsc_conf_move_key() {
	local src="$1" dst="$2" key="$3" line
	[ -f "$src" ] && [ -f "$dst" ] || return 1
	line="$(grep -E "^${key}=" "$src" 2>/dev/null | head -n1)"
	[ -n "$line" ] || return 1
	qsc_conf_delete_key_atomic "$dst" "$key"
	printf '%s\n' "$line" >>"$dst" 2>/dev/null
	return 0
}

qsc_conf_strip_keys_from() {
	local file="$1"
	[ -f "$file" ] || return 0
	shift
	[ "$#" -gt 0 ] || return 0
	qsc_conf_delete_keys_atomic "$file" "$@"
}

qsc_conf_migrate_split() {
	local conf="${CONF:-}"
	local power="${POWER_CONF:-}"
	local notify="${NOTIFY_CONF:-}"
	local k migrated=0
	[ -n "$conf" ] && [ -f "$conf" ] || return 0
	[ -n "$power" ] && [ -n "$notify" ] || return 0

	# 先治愈 NUL 损坏，再迁移键
	qsc_conf_heal_all

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
	# 旧 shut_down → low_batt_shutdown（仅当新键尚未存在）
	if grep -E '^shut_down=' "$conf" >/dev/null 2>&1; then
		_sd="$(sed -n 's/^shut_down=//p' "$conf" 2>/dev/null | head -n1 | tr -d ' \r\n')"
		if [ -n "$_sd" ] && [ "$_sd" != "0" ] &&
			! grep -E '^low_batt_shutdown=' "$notify" >/dev/null 2>&1; then
			printf 'low_batt_shutdown=%s\n' "$_sd" >>"$notify" 2>/dev/null && migrated=1
		fi
		qsc_conf_delete_key_atomic "$conf" "shut_down"
	fi
	if grep -E '^notify_quiet_schedule=' "$conf" >/dev/null 2>&1; then
		qsc_conf_delete_key_atomic "$notify" "notify_quiet_schedule"
		grep -E '^notify_quiet_schedule=' "$conf" >>"$notify" 2>/dev/null && migrated=1
	fi

	# 省电旋钮：只删双源，不覆盖新版 power.conf
	# shellcheck disable=SC2086
	qsc_conf_strip_keys_from "$conf" $QSC_POWER_STRIP_ONLY $QSC_POWER_KEEP night_schedule
	# shellcheck disable=SC2086
	qsc_conf_strip_keys_from "$conf" $QSC_NOTIFY_KEYS notify_quiet_schedule shut_down

	[ "$migrated" = "1" ] && type qsc_log >/dev/null 2>&1 &&
		qsc_log info "已整理省电/通知配置（间隔用新版默认，偏好/通知已迁出）"
	return 0
}
