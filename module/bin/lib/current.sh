#!/system/bin/sh
# 电流控制：模拟旁路 / 慢充 / 默认限流 / 温度阶梯 / 游戏限流
# 配置：config/current.json；总开关 current_control=0 时整段跳过。
# 写入策略：
# - 从 battery_current 读取节点列表，对本机存在的路径全部写入
# - 额外合并开机探测的 *restrict*_cur*（list_charge_current）
# - 限流前按 restricted 写入策略参数（如 qcom restrict_chg）
# 安全约束：
# - 不写 /data/vendor/thermal；不做 MCA/内核补丁
# - 不写 charge_control_limit / thermal_input_current 等非电流策略节点
# - 危险节点名、写入无效/读回不像 µA 上限的节点会跳过或拉黑

# JSONC 解析
[ -n "$QSC_JSONC_LOADED" ] || {
	if [ -f "${LIBDIR:-}/jsonc.sh" ]; then
		. "$LIBDIR/jsonc.sh"
	elif [ -f "${0%/*}/jsonc.sh" ]; then
		. "${0%/*}/jsonc.sh"
	fi
	QSC_JSONC_LOADED=1
}

# 禁止写入：档位/温控/瞬时类
# battery_current 默认四路径中的 fast_charge_current / constant_charge_current 不在此拒绝
QSC_CURRENT_DENY="\
charge_control_limit \
thermal_input_current \
charge_current \
current_now \
voltage_now \
status \
capacity \
temp \
type \
uevent"

# 配置缺失/数组为空时的兜底四路径（与 current.json 默认一致）
QSC_CURRENT_SAFE_FALLBACK="\
/sys/class/power_supply/battery/fast_charge_current \
/sys/class/power_supply/battery/current_max \
/sys/class/power_supply/battery/constant_charge_current \
/sys/class/power_supply/battery/constant_charge_current_max"

# 可选硬件旁路节点（仅探测，不强制创建）
QSC_BYPASS_NODE_CANDIDATES="\
/sys/class/qcom-battery/bypass_charging_enable \
/sys/class/power_supply/battery/enable_bypass_mode"

# µA → 可读 mA（日志用）
qsc_fmt_ma() {
	local ua="$1"
	case "$ua" in
		""|*[!0-9]*) printf '%s' "$ua" ;;
		*) printf '%smA' "$((ua / 1000))" ;;
	esac
}

# 节点路径缩短：保留末两级
qsc_node_short() {
	local p="$1" a b
	b="${p##*/}"
	a="${p%/*}"
	a="${a##*/}"
	if [ -n "$a" ] && [ "$a" != "$p" ]; then
		printf '%s/%s' "$a" "$b"
	else
		printf '%s' "$b"
	fi
}

qsc_nodes_short() {
	local n out=""
	for n in $1; do
		[ -n "$n" ] || continue
		if [ -n "$out" ]; then
			out="$out $(qsc_node_short "$n")"
		else
			out="$(qsc_node_short "$n")"
		fi
	done
	printf '%s' "$out"
}

qsc_current_conf_get() {
	local key="$1"
	[ -f "$CURRENT_CONF" ] || return 1
	qsc_jsonc_get "$CURRENT_CONF" "$key"
}

qsc_current_conf_get_strings() {
	local key="$1"
	[ -f "$CURRENT_CONF" ] || return 1
	qsc_jsonc_get_strings "$CURRENT_CONF" "$key"
}

qsc_current_node_denied() {
	local node="$1" base deny
	base="${node##*/}"
	for deny in $QSC_CURRENT_DENY; do
		[ "$base" = "$deny" ] && return 0
	done
	return 1
}

qsc_current_node_blacklisted() {
	local node="$1"
	[ -f "$DATADIR/current_node_blacklist" ] || return 1
	grep -Fqx "$node" "$DATADIR/current_node_blacklist" 2>/dev/null
}

qsc_current_blacklist_node() {
	local node="$1" why="$2"
	[ -n "$node" ] || return 0
	mkdir -p "$DATADIR" 2>/dev/null
	grep -Fqx "$node" "$DATADIR/current_node_blacklist" 2>/dev/null && return 0
	echo "$node" >>"$DATADIR/current_node_blacklist"
	qsc_current_clear_write_fail "$node"
	echo 1 >"$DATADIR/current_force_log"
	echo "$(date +%F_%T) 已排除无效节点 $(qsc_node_short "$node")：$why（后续改用剩余节点）" >>"$LOG_FILE"
}

# 写入失败：连续 3 次才拉黑
# 计数文件每行：「次数 路径」（不用 |，避免部分机 grep 把 | 当正则导致永远第 1 次）
qsc_current_mark_write_fail() {
	local node="$1" why="$2" line cnt=0 c n
	local f="$DATADIR/current_node_failcnt"
	local tmp="$DATADIR/.failcnt_tmp"
	[ -n "$node" ] || return 0
	mkdir -p "$DATADIR" 2>/dev/null
	: >"$tmp"
	if [ -f "$f" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			line="$(printf '%s' "$line" | tr -d '\r')"
			[ -n "$line" ] || continue
			c="${line%% *}"
			n="${line#* }"
			if [ "$n" = "$node" ]; then
				case "$c" in
					""|*[!0-9]*) cnt=0 ;;
					*) cnt="$c" ;;
				esac
				continue
			fi
			printf '%s\n' "$line" >>"$tmp"
		done <"$f"
	fi
	cnt=$((cnt + 1))
	if [ "$cnt" -ge 3 ]; then
		mv "$tmp" "$f"
		qsc_current_blacklist_node "$node" "$why"
		return 0
	fi
	printf '%s %s\n' "$cnt" "$node" >>"$tmp"
	mv "$tmp" "$f"
	echo "$(date +%F_%T) 节点 $(qsc_node_short "$node") 写入未生效（第${cnt}/3次，满3次将排除）：$why" >>"$LOG_FILE"
}

qsc_current_clear_write_fail() {
	local node="$1" line c n
	local f="$DATADIR/current_node_failcnt"
	local tmp="$DATADIR/.failcnt_tmp"
	[ -n "$node" ] || return 0
	[ -f "$f" ] || return 0
	: >"$tmp"
	while IFS= read -r line || [ -n "$line" ]; do
		line="$(printf '%s' "$line" | tr -d '\r')"
		[ -n "$line" ] || continue
		n="${line#* }"
		[ "$n" = "$node" ] && continue
		printf '%s\n' "$line" >>"$tmp"
	done <"$f"
	mv "$tmp" "$f"
}

# current.json 的 mtime/size 变化时清拉黑（解析结果不稳定时不再误清计数）
qsc_current_sync_conf_guard() {
	local meta_file="$DATADIR/current_conf_meta"
	local new=""
	[ -f "$CURRENT_CONF" ] || return 0
	mkdir -p "$DATADIR" 2>/dev/null
	new="$(stat -c '%Y %s' "$CURRENT_CONF" 2>/dev/null)"
	[ -n "$new" ] || new="$(ls -l "$CURRENT_CONF" 2>/dev/null)"
	[ -n "$new" ] || return 0
	if [ -f "$meta_file" ] && [ "$(cat "$meta_file" 2>/dev/null)" = "$new" ]; then
		return 0
	fi
	if [ -f "$meta_file" ]; then
		rm -f "$DATADIR/current_node_blacklist" "$DATADIR/current_node_failcnt"
		rm -f "${LIST_CHARGE_CURRENT:-$DATADIR/list_charge_current}"
		echo "$(date +%F_%T) 电流控制：检测到 current.json 变更，已清空节点拉黑/失败计数" >>"$LOG_FILE"
	fi
	printf '%s\n' "$new" >"$meta_file"
}

qsc_current_refresh_restrict_list() {
	local list="${LIST_CHARGE_CURRENT:-$DATADIR/list_charge_current}"
	mkdir -p "$DATADIR" 2>/dev/null
	find /sys/class /sys/devices /sys/module -type f -name '*restrict*_cur*' 2>/dev/null \
		| egrep -i -v 'usb' \
		| sort -u >"$list"
}

# 将节点列表文本追加进 QSC_CURRENT_NODES（仅保留存在的路径，去重）
qsc_current_append_existing() {
	local list_file="$1" node
	[ -f "$list_file" ] || return 0
	while IFS= read -r node || [ -n "$node" ]; do
		node="$(echo "$node" | tr -d ' \r\n')"
		case "$node" in
			/sys/*|/proc/*)
				[ -f "$node" ] || continue
				case " $QSC_CURRENT_NODES " in
					*" $node "*) continue ;;
				esac
				if qsc_current_node_denied "$node"; then
					echo "$(date +%F_%T) 忽略危险电流节点配置：$node" >>"$LOG_FILE"
					continue
				fi
				qsc_current_node_blacklisted "$node" && continue
				QSC_CURRENT_NODES="$QSC_CURRENT_NODES $node"
				;;
		esac
	done <"$list_file"
}

# 合并开机探测的 *restrict*_cur*
qsc_current_append_restrict_cur() {
	local list="${LIST_CHARGE_CURRENT:-$DATADIR/list_charge_current}"
	[ -f "$list" ] || qsc_current_refresh_restrict_list
	[ -f "$list" ] || return 0
	qsc_current_append_existing "$list"
}

# 按 restricted 配置写非 µA 策略节点（若存在）
qsc_current_apply_restricted() {
	local line route val cur list_file="$DATADIR/.restricted_tmp"
	: >"$list_file"
	qsc_current_conf_get_strings restricted >"$list_file" 2>/dev/null || : >"$list_file"
	[ -s "$list_file" ] || {
		rm -f "$list_file"
		return 0
	}
	while IFS= read -r line || [ -n "$line" ]; do
		line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r')"
		[ -n "$line" ] || continue
		case "$line" in
			*" value="*)
				route="${line%% value=*}"
				val="${line#* value=}"
				;;
			*"|"*)
				route="${line%%|*}"
				val="${line#*|}"
				;;
			*)
				continue
				;;
		esac
		route="$(echo "$route" | tr -d ' \r\n')"
		val="$(echo "$val" | tr -d ' \r\n')"
		[ -f "$route" ] || continue
		[ -n "$val" ] || continue
		chmod 0644 "$route" 2>/dev/null
		cur="$(cat "$route" 2>/dev/null | tr -d ' \r\n')"
		if [ -n "$cur" ] && [ "$cur" != "$val" ]; then
			echo "$val" >"$route" 2>/dev/null || true
		fi
	done <"$list_file"
	rm -f "$list_file"
}

qsc_current_build_nodes() {
	local node note=""
	QSC_CURRENT_NODES=""

	qsc_current_sync_conf_guard

	qsc_current_conf_get_strings battery_current >"$DATADIR/.current_nodes_tmp" 2>/dev/null || : >"$DATADIR/.current_nodes_tmp"
	if [ -s "$DATADIR/.current_nodes_tmp" ]; then
		qsc_current_append_existing "$DATADIR/.current_nodes_tmp"
	fi
	rm -f "$DATADIR/.current_nodes_tmp"

	# 配置为空或节点均不存在：用兜底四路径
	if [ -z "$(echo "$QSC_CURRENT_NODES" | tr -d ' ')" ]; then
		for node in $QSC_CURRENT_SAFE_FALLBACK; do
			[ -f "$node" ] || continue
			qsc_current_node_denied "$node" && continue
			qsc_current_node_blacklisted "$node" && continue
			case " $QSC_CURRENT_NODES " in
				*" $node "*) continue ;;
			esac
			QSC_CURRENT_NODES="$QSC_CURRENT_NODES $node"
		done
	fi

	qsc_current_append_restrict_cur

	if [ -z "$(echo "$QSC_CURRENT_NODES" | tr -d ' ')" ]; then
		if [ "$(cat "$DATADIR/current_mode_tag" 2>/dev/null)" != "无可用节点" ]; then
			echo "$(date +%F_%T) 电流控制：battery_current 无可用节点，跳过写入" >>"$LOG_FILE"
			echo "无可用节点" >"$DATADIR/current_mode_tag"
		fi
		QSC_CURRENT_NODES=""
		return 1
	fi

	note="nodes:$QSC_CURRENT_NODES"
	if [ "$(cat "$DATADIR/current_node_note" 2>/dev/null)" != "$note" ]; then
		echo 1 >"$DATADIR/current_force_log"
		echo "$(date +%F_%T) 电流控制：将写入 $(qsc_nodes_short "$QSC_CURRENT_NODES")" >>"$LOG_FILE"
		echo "$note" >"$DATADIR/current_node_note"
	fi
	return 0
}

# 探测可用硬件旁路节点；写入 QSC_BYPASS_NODE（可能为空）
qsc_bypass_probe_node() {
	local node cur
	QSC_BYPASS_NODE=""
	for node in $QSC_BYPASS_NODE_CANDIDATES; do
		[ -f "$node" ] || continue
		cur="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
		case "$cur" in
			0|1) QSC_BYPASS_NODE="$node"; return 0 ;;
		esac
	done
	return 1
}

qsc_bypass_hw_on() {
	local node="$1"
	local prev cur
	[ -n "$node" ] && [ -f "$node" ] || return 1
	prev="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
	case "$prev" in
		0|1) ;;
		*) return 1 ;;
	esac
	echo "$prev" >"$DATADIR/bypass_node_prev" 2>/dev/null
	echo "$node" >"$DATADIR/bypass_node_path" 2>/dev/null
	chmod 0644 "$node" 2>/dev/null
	echo "1" >"$node" 2>/dev/null || return 1
	cur="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
	[ "$cur" = "1" ]
}

qsc_bypass_hw_off() {
	local node prev
	node="$(cat "$DATADIR/bypass_node_path" 2>/dev/null)"
	prev="$(cat "$DATADIR/bypass_node_prev" 2>/dev/null)"
	[ -z "$node" ] && node="$QSC_BYPASS_NODE"
	[ -n "$node" ] && [ -f "$node" ] || {
		rm -f "$DATADIR/bypass_node_path" "$DATADIR/bypass_node_prev"
		return 0
	}
	case "$prev" in
		0|1) ;;
		*) prev=0 ;;
	esac
	chmod 0644 "$node" 2>/dev/null
	echo "$prev" >"$node" 2>/dev/null
	rm -f "$DATADIR/bypass_node_path" "$DATADIR/bypass_node_prev"
	return 0
}

# 校验节点读回值是否像 µA 上限（拒绝档位索引）
qsc_current_value_plausible() {
	local cur="$1" target="$2"
	case "$cur" in
		""|*[!0-9]*) return 1 ;;
	esac
	# 读回像档位（0–32）却要写超大 µA → 危险
	if [ "$cur" -le 64 ] && [ "$target" -gt 1000 ]; then
		return 1
	fi
	# 读回像 mA（常见 500–10000）而目标是 µA 量级：允许写；档位误判靠上方规则拦截
	# 读回异常巨大（>20000000）跳过
	if [ "$cur" -gt 20000000 ]; then
		return 1
	fi
	return 0
}

# 写入电流目标。副作用（供日志）：
#   QSC_CW_FROM / QSC_CW_TO：本轮实际写入前后值
#   QSC_CW_REACHED=1：已到最终目标；QSC_CW_STEPPING=1：本轮只是降流步进
qsc_current_write_target() {
	local target="$1"
	local node cur next wrote=0 after at_target=0 step_to=""
	QSC_CW_FROM=""
	QSC_CW_TO=""
	QSC_CW_REACHED=0
	QSC_CW_STEPPING=0
	case "$target" in
		""|*[!0-9]*) return 1 ;;
	esac
	# 非旁路目标时避免过小电流（保留模拟旁路的 0）
	if [ "$target" != "0" ] && [ "$target" -lt 50000 ]; then
		target=50000
	fi
	# 硬顶：防止配置误填把 µA 写成天文数字
	if [ "$target" -gt 10000000 ]; then
		target=10000000
	fi

	for node in $QSC_CURRENT_NODES; do
		[ -f "$node" ] || continue
		qsc_current_node_denied "$node" && continue
		qsc_current_node_blacklisted "$node" && continue

		chmod 0644 "$node" 2>/dev/null
		cur="$(cat "$node" 2>/dev/null | egrep -v '\-|\+' | tr -d ' \r\n')"
		case "$cur" in
			""|*[!0-9]*) continue ;;
		esac

		if ! qsc_current_value_plausible "$cur" "$target"; then
			qsc_current_blacklist_node "$node" "读回值不像µA上限(现$(qsc_fmt_ma "$cur")/目标$(qsc_fmt_ma "$target"))"
			continue
		fi

		if [ "$cur" = "$target" ]; then
			at_target=1
			QSC_CW_REACHED=1
			QSC_CW_FROM="$cur"
			QSC_CW_TO="$cur"
			qsc_current_clear_write_fail "$node"
			continue
		fi

		# 高于目标：分步降流（每次约 -500000µA）；低于目标：直接抬流到位
		step_to="$target"
		if [ "$cur" -gt "$target" ]; then
			next=$((cur - 500000))
			if [ "$next" -gt "$target" ] && [ "$target" != "0" ]; then
				step_to="$next"
			fi
			if ! echo "$step_to" >"$node" 2>/dev/null; then
				qsc_current_mark_write_fail "$node" "无法写入(权限或只读)"
				continue
			fi
		else
			if ! echo "$target" >"$node" 2>/dev/null; then
				qsc_current_mark_write_fail "$node" "无法写入(权限或只读)"
				continue
			fi
			step_to="$target"
		fi

		after="$(cat "$node" 2>/dev/null | egrep -v '\-|\+' | tr -d ' \r\n')"
		case "$after" in
			""|*[!0-9]*)
				qsc_current_mark_write_fail "$node" "写后无法读回有效数值"
				continue
				;;
		esac

		# 写后读回仍像档位 → 拉黑，避免每 3s 抢写
		if [ "$after" -le 64 ] && [ "$target" -gt 1000 ]; then
			qsc_current_blacklist_node "$node" "写后读回仍像档位(after=$after)"
			continue
		fi

		# 内核忽略写入：读回未变且仍不是目标 → 计次，连续 3 次再拉黑
		if [ "$after" = "$cur" ] && [ "$cur" != "$target" ]; then
			qsc_current_mark_write_fail "$node" "内核未接受(读回仍$(qsc_fmt_ma "$cur")，目标$(qsc_fmt_ma "$target"))"
			continue
		fi

		qsc_current_clear_write_fail "$node"
		wrote=1
		if [ -z "$QSC_CW_FROM" ]; then
			QSC_CW_FROM="$cur"
			QSC_CW_TO="$after"
			if [ "$after" = "$target" ]; then
				QSC_CW_REACHED=1
				QSC_CW_STEPPING=0
			elif [ "$cur" -gt "$target" ] && [ "$after" -lt "$cur" ]; then
				QSC_CW_STEPPING=1
				QSC_CW_REACHED=0
			else
				QSC_CW_STEPPING=0
				QSC_CW_REACHED=0
			fi
		fi
	done

	if [ "$at_target" = "1" ] && [ "$wrote" != "1" ]; then
		QSC_CW_REACHED=1
		QSC_CW_STEPPING=0
	fi
	[ "$wrote" = "1" ] || [ "$at_target" = "1" ]
}

qsc_current_now_ua() {
	local c
	c="$(qsc_safe_cat /sys/class/power_supply/battery/current_now 2>/dev/null)"
	c="$(echo "$c" | sed 's/-//g' | tr -d ' \r\n')"
	echo "${c:-0}"
}

# 仅匹配前台窗口，避免后台进程误触发限流
qsc_current_game_hit() {
	local pkg focus list_file
	focus="$(dumpsys window 2>/dev/null | grep 'mCurrentFocus' | tail -1)"
	[ -z "$focus" ] && focus="$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1)"
	[ -n "$focus" ] || return 1
	list_file="$DATADIR/.app_list_tmp"
	qsc_current_conf_get_strings app_list >"$list_file" 2>/dev/null || return 1
	[ -s "$list_file" ] || {
		rm -f "$list_file"
		return 1
	}
	while IFS= read -r pkg || [ -n "$pkg" ]; do
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
		[ -n "$pkg" ] || continue
		if echo "$focus" | grep -q "$pkg"; then
			rm -f "$list_file"
			return 0
		fi
	done <"$list_file"
	rm -f "$list_file"
	return 1
}

# HH:MM → 当日分钟数（0–1439）；非法返回空
qsc_hm_to_min() {
	local hm="$1" h m
	hm="$(printf '%s' "$hm" | tr -d ' \r\n')"
	case "$hm" in
		[0-1][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9]) ;;
		*) return 1 ;;
	esac
	h="${hm%%:*}"
	m="${hm##*:}"
	# 去前导零，避免 08 被部分 shell 当八进制
	h="${h#0}"
	m="${m#0}"
	[ -n "$h" ] || h=0
	[ -n "$m" ] || m=0
	echo $((h * 60 + m))
}

# 当前时刻是否落在 start-end（支持跨天：22:00-08:00）
qsc_time_in_range() {
	local start="$1" end="$2" now_hm now_m start_m end_m
	now_hm="$(date +%H:%M 2>/dev/null)" || return 1
	now_m="$(qsc_hm_to_min "$now_hm")" || return 1
	start_m="$(qsc_hm_to_min "$start")" || return 1
	end_m="$(qsc_hm_to_min "$end")" || return 1
	if [ "$start_m" -le "$end_m" ]; then
		[ "$now_m" -ge "$start_m" ] && [ "$now_m" -lt "$end_m" ]
	else
		# 跨天：now >= start 或 now < end
		[ "$now_m" -ge "$start_m" ] || [ "$now_m" -lt "$end_m" ]
	fi
}

# bypass_schedule 字符串数组任一段命中则返回 0
qsc_bypass_schedule_hit() {
	local range start end list_file
	list_file="$DATADIR/.bypass_sched_tmp"
	qsc_current_conf_get_strings bypass_schedule >"$list_file" 2>/dev/null || {
		rm -f "$list_file"
		return 1
	}
	while IFS= read -r range || [ -n "$range" ]; do
		range="$(printf '%s' "$range" | tr -d ' \r\n')"
		[ -n "$range" ] || continue
		case "$range" in
			*-*-*) continue ;; # 拒绝异常多段
			*-*)
				start="${range%%-*}"
				end="${range#*-}"
				if qsc_time_in_range "$start" "$end"; then
					rm -f "$list_file"
					return 0
				fi
				;;
		esac
	done <"$list_file"
	rm -f "$list_file"
	return 1
}

# 依赖外部环境：battery_level temperature；且未触发供电开关停充
qsc_apply_current_control() {
	local enable battery_stop slow_charge temp_cur
	local limit1 limit2 cur1 cur2 def_max app_on app_cur
	local reason target now_c battery_stop_1 prev_tag write_ok reached_flag
	local mode_tag="" bypass_mode safety_temp bypass_temp
	local want_bypass=0 used_hw=0 by_level=0 by_temp=0 by_sched=0
	local reasons=""

	[ -f "$CURRENT_CONF" ] || return 0
	enable="$(qsc_current_conf_get current_control)"
	[ "$enable" = "1" ] || {
		qsc_bypass_hw_off
		return 0
	}

	qsc_current_build_nodes || return 0
	[ -n "$(echo "$QSC_CURRENT_NODES" | tr -d ' ')" ] || return 0

	# 限流前先写 restricted 类参数
	qsc_current_apply_restricted

	battery_stop="$(qsc_current_conf_get battery_stop)"
	[ -z "$battery_stop" ] && battery_stop=110
	bypass_temp="$(qsc_current_conf_get bypass_temp)"
	[ -z "$bypass_temp" ] && bypass_temp=110
	slow_charge="$(qsc_current_conf_get slow_charge)"
	[ -z "$slow_charge" ] && slow_charge=110
	temp_cur="$(qsc_current_conf_get temperature_current)"
	limit1="$(qsc_current_conf_get default_current_limit)"
	limit2="$(qsc_current_conf_get temperature_current_limit)"
	cur1="$(qsc_current_conf_get default_current_max_limit)"
	cur2="$(qsc_current_conf_get constant_current_max)"
	def_max="$(qsc_current_conf_get default_current_max)"
	app_on="$(qsc_current_conf_get app_limit)"
	app_cur="$(qsc_current_conf_get app_current_max)"
	bypass_mode="$(qsc_current_conf_get bypass_mode)"
	safety_temp="$(qsc_current_conf_get safety_temp_max)"
	[ -z "$def_max" ] && def_max=5000000
	[ -z "$cur1" ] && cur1=1500000
	[ -z "$cur2" ] && cur2=100000
	[ -z "$app_cur" ] && app_cur=200000
	[ -z "$limit1" ] && limit1=40
	[ -z "$limit2" ] && limit2=45
	[ -z "$bypass_mode" ] && bypass_mode="sim"
	[ -z "$safety_temp" ] && safety_temp=48
	# 二限电流下限保护（非旁路）
	[ "$cur2" -lt 50000 ] 2>/dev/null && cur2=50000
	[ "$app_cur" -lt 50000 ] 2>/dev/null && app_cur=50000
	[ "$def_max" -gt 10000000 ] 2>/dev/null && def_max=10000000

	# 旁路触发：电量 / 温度 / 时段 任一满足（OR）
	if [ "$battery_stop" -le 100 ] && [ -n "$battery_level" ] && [ "$battery_level" -ge "$battery_stop" ]; then
		by_level=1
		reasons="${reasons}电量 "
	fi
	if [ "$bypass_temp" -le 100 ] && [ -n "$temperature" ] && [ "$temperature" -ge "$bypass_temp" ]; then
		by_temp=1
		reasons="${reasons}温度 "
	fi
	if qsc_bypass_schedule_hit; then
		by_sched=1
		reasons="${reasons}时段 "
	fi
	if [ "$by_level$by_temp$by_sched" != "000" ]; then
		want_bypass=1
		target=0
		reasons="$(printf '%s' "$reasons" | sed 's/ $//' | tr ' ' '/')"
		mode_tag="旁路·${reasons}"
	fi

	# 优先级：旁路 > 二限/旁路回补/慢充 > 游戏限流 > 一限 > 默认
	if [ "$want_bypass" != "1" ]; then
		battery_stop_1=$((battery_stop - 1))
		if [ "$temp_cur" = "1" ] && [ -n "$temperature" ] && [ "$temperature" -ge "$limit2" ]; then
			target="$cur2"
			mode_tag="二限温控"
		elif [ "$battery_stop" -le 100 ] && [ "$battery_level" = "$battery_stop_1" ]; then
			target="$cur2"
			mode_tag="旁路回补"
		elif [ "$slow_charge" -le 100 ] && [ "$battery_level" -ge "$slow_charge" ]; then
			target="$cur2"
			mode_tag="慢充"
		elif [ "$app_on" = "1" ] && qsc_current_game_hit; then
			target="$app_cur"
			mode_tag="游戏限流"
		elif [ "$temp_cur" = "1" ] && [ -n "$temperature" ] && [ "$temperature" -ge "$limit1" ]; then
			target="$cur1"
			mode_tag="一限温控"
		else
			target="$def_max"
			mode_tag="默认限流"
		fi
	fi

	# 高温保护：不写 0 / 不开硬件旁路，改用二限小电流
	if [ "$want_bypass" = "1" ] && [ -n "$temperature" ] && [ "$temperature" -ge "$safety_temp" ]; then
		want_bypass=0
		target="$cur2"
		mode_tag="高温保护"
		qsc_bypass_hw_off
	fi

	# 可选：本机确有旁路节点且 bypass_mode=auto 时尝试硬件旁路；失败则回退写电流
	if [ "$want_bypass" = "1" ] && [ "$bypass_mode" = "auto" ]; then
		if qsc_bypass_probe_node && qsc_bypass_hw_on "$QSC_BYPASS_NODE"; then
			used_hw=1
			mode_tag="节点旁路"
			target=0
		else
			qsc_bypass_hw_off
		fi
	else
		qsc_bypass_hw_off
	fi

	if [ "$used_hw" = "1" ]; then
		reason="${mode_tag}:hw"
		if [ "$(cat "$DATADIR/current_mode_tag" 2>/dev/null)" != "$reason" ]; then
			now_c="$(qsc_current_now_ua)"
			echo "$(date +%F_%T) 电量$battery_level ${mode_tag}：节点$QSC_BYPASS_NODE 实时电流${now_c} 温度${temperature}" >>"$LOG_FILE"
			echo "$reason" >"$DATADIR/current_mode_tag"
		fi
		return 0
	fi

	# 同目标且已到位：冷却 30s，避免每 3s 空转抢写
	# 降流步进未到位时不冷却，主循环约每 3s 继续下一阶
	reason="${mode_tag}:${target}"
	prev_tag="$(cat "$DATADIR/current_mode_tag" 2>/dev/null)"
	reached_flag="$(cat "$DATADIR/current_reached" 2>/dev/null)"
	if [ "$prev_tag" = "$reason" ] && [ "$reached_flag" = "1" ]; then
		now_ts="$(date +%s 2>/dev/null)"
		last_ts="$(cat "$DATADIR/current_write_ts" 2>/dev/null)"
		if [ -n "$now_ts" ] && [ -n "$last_ts" ]; then
			case "${now_ts}${last_ts}" in
				*[!0-9]*) ;;
				*)
					if [ $((now_ts - last_ts)) -lt 30 ]; then
						return 0
					fi
					;;
			esac
		fi
	fi

	write_ok=0
	qsc_current_write_target "$target" && write_ok=1
	now_c="$(qsc_current_now_ua)"
	force_log="$(cat "$DATADIR/current_force_log" 2>/dev/null)"
	nodes_s="$(qsc_nodes_short "${QSC_CURRENT_NODES:-}")"
	tgt_s="$(qsc_fmt_ma "$target")"
	now_s="$(qsc_fmt_ma "$now_c")"

	if [ "$write_ok" != "1" ]; then
		# 同原因失败默认只记一次；节点集合变更后必须再记一次成败，避免「改用节点」后无下文
		if [ "$prev_tag" != "fail:$reason" ] || [ "$force_log" = "1" ]; then
			echo "$(date +%F_%T) 电量$battery_level 限流未生效：${mode_tag} 目标${tgt_s} 节点${nodes_s:-无} 实时约${now_s}（内核未接受或节点不可写）" >>"$LOG_FILE"
			echo "fail:$reason" >"$DATADIR/current_mode_tag"
			echo 0 >"$DATADIR/current_reached"
			rm -f "$DATADIR/current_force_log"
		fi
		return 0
	fi

	if [ "${QSC_CW_STEPPING:-0}" = "1" ]; then
		# 降流未到位：每阶都记日志，并允许下一轮继续步进
		echo "$(date +%F_%T) 电量$battery_level ${mode_tag}降流中：$(qsc_fmt_ma "$QSC_CW_FROM")→$(qsc_fmt_ma "$QSC_CW_TO")（目标${tgt_s}）节点${nodes_s} 实时约${now_s} 温度${temperature}" >>"$LOG_FILE"
		echo "$reason" >"$DATADIR/current_mode_tag"
		echo 0 >"$DATADIR/current_reached"
		date +%s >"$DATADIR/current_write_ts" 2>/dev/null
		rm -f "$DATADIR/current_force_log"
		return 0
	fi

	# 抬流直接到位，或降流最后一阶 / 已是目标
	if [ "$prev_tag" != "$reason" ] || [ "$reached_flag" != "1" ] || [ "$force_log" = "1" ]; then
		if [ "${QSC_CW_FROM:-}" != "${QSC_CW_TO:-}" ] && [ -n "${QSC_CW_FROM:-}" ]; then
			echo "$(date +%F_%T) 电量$battery_level 限流已生效：${mode_tag} $(qsc_fmt_ma "$QSC_CW_FROM")→$(qsc_fmt_ma "$QSC_CW_TO")（目标${tgt_s}）节点${nodes_s} 实时约${now_s} 温度${temperature}" >>"$LOG_FILE"
		else
			echo "$(date +%F_%T) 电量$battery_level 限流已到位：${mode_tag} 目标${tgt_s} 节点${nodes_s} 实时约${now_s} 温度${temperature}" >>"$LOG_FILE"
		fi
	fi
	echo "$reason" >"$DATADIR/current_mode_tag"
	echo 1 >"$DATADIR/current_reached"
	date +%s >"$DATADIR/current_write_ts" 2>/dev/null
	rm -f "$DATADIR/current_force_log"
}
