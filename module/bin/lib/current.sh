#!/system/bin/sh
# 电流控制：模拟旁路 / 慢充 / 默认限流 / 温度阶梯 / 游戏限流
# 配置：config/current.json；总开关 current_control=0 时整段跳过。
# 安全约束（force_battery_current=0 时）：
# - 不写 /data/vendor/thermal；不做 MCA/内核补丁
# - 不写 charge_control_limit / thermal_input_current 等非电流策略节点
# - 未配置 battery_current 时只选「单一」探测白名单节点
# - force_battery_current=1 且 battery_current 非空：按配置数组全量写入（跳过黑名单）
# - force_battery_current=1 但数组为空：与关闭相同，回退自动探测

# JSONC 解析
[ -n "$QSC_JSONC_LOADED" ] || {
	if [ -f "${LIBDIR:-}/jsonc.sh" ]; then
		. "$LIBDIR/jsonc.sh"
	elif [ -f "${0%/*}/jsonc.sh" ]; then
		. "${0%/*}/jsonc.sh"
	fi
	QSC_JSONC_LOADED=1
}

# 禁止写入：档位/温控/瞬时类（force_battery_current=1 时跳过）
# 默认四路径中的 fast_charge_current / constant_charge_current 已纳入探测白名单，不在此拒绝
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

# 自动探测白名单：先按配置四路径顺序，再补其它常见上限节点；取「第一个存在且未拒绝的」
QSC_CURRENT_SAFE_FALLBACK="\
/sys/class/power_supply/battery/fast_charge_current \
/sys/class/power_supply/battery/current_max \
/sys/class/power_supply/battery/constant_charge_current \
/sys/class/power_supply/battery/constant_charge_current_max \
/sys/class/power_supply/battery/fast_charge_current_max \
/sys/class/power_supply/battery/input_current_max"

# 可选硬件旁路节点（仅探测，不强制创建）
QSC_BYPASS_NODE_CANDIDATES="\
/sys/class/qcom-battery/bypass_charging_enable \
/sys/class/power_supply/battery/enable_bypass_mode"

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

qsc_current_is_mtk() {
	[ -d /proc/mtk_battery_cmd ] && return 0
	[ -f /sys/devices/platform/charger/mtk_charger ] && return 0
	getprop ro.board.platform 2>/dev/null | grep -qiE 'mt[0-9]|dimensity|helio' && return 0
	getprop ro.hardware 2>/dev/null | grep -qiE '^mt' && return 0
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
	echo "$(date +%F_%T) 电流节点拉黑：$node（$why）" >>"$LOG_FILE"
}

qsc_current_force_on() {
	local v
	v="$(qsc_current_conf_get force_battery_current 2>/dev/null)"
	[ "$v" = "1" ] || [ "$v" = "true" ]
}

# 将节点列表文本追加进 QSC_CURRENT_NODES（仅保留存在的路径）
qsc_current_append_existing() {
	local list_file="$1" force="$2" node
	while IFS= read -r node || [ -n "$node" ]; do
		case "$node" in
			/sys/*|/proc/*)
				[ -f "$node" ] || continue
				if [ "$force" != "1" ]; then
					if qsc_current_node_denied "$node"; then
						echo "$(date +%F_%T) 忽略危险电流节点配置：$node" >>"$LOG_FILE"
						continue
					fi
					qsc_current_node_blacklisted "$node" && continue
				fi
				QSC_CURRENT_NODES="$QSC_CURRENT_NODES $node"
				;;
		esac
	done <"$list_file"
}

qsc_current_build_nodes() {
	local node first="" configured=0 force=0
	QSC_CURRENT_NODES=""
	QSC_CURRENT_NODES_USER=0
	QSC_CURRENT_FORCE=0

	# 仅当开关开且数组非空时才强制；空数组回退默认逻辑
	if qsc_current_force_on; then
		force=1
	fi

	qsc_current_conf_get_strings battery_current >"$DATADIR/.current_nodes_tmp" 2>/dev/null || : >"$DATADIR/.current_nodes_tmp"
	if [ -s "$DATADIR/.current_nodes_tmp" ]; then
		qsc_current_append_existing "$DATADIR/.current_nodes_tmp" "$force"
		[ -n "$(echo "$QSC_CURRENT_NODES" | tr -d ' ')" ] && configured=1
	fi
	rm -f "$DATADIR/.current_nodes_tmp"

	if [ "$configured" = "1" ]; then
		QSC_CURRENT_NODES_USER=1
		if [ "$force" = "1" ]; then
			QSC_CURRENT_FORCE=1
			if [ "$(cat "$DATADIR/current_node_note" 2>/dev/null)" != "force-cfg" ]; then
				echo "$(date +%F_%T) 电流控制：force_battery_current=1，按配置数组写入$QSC_CURRENT_NODES" >>"$LOG_FILE"
				echo "force-cfg" >"$DATADIR/current_node_note"
			fi
		fi
		return 0
	fi

	# 未配置（或强制开但数组为空/节点均不存在）：只选一个安全节点
	QSC_CURRENT_FORCE=0
	for node in $QSC_CURRENT_SAFE_FALLBACK; do
		[ -f "$node" ] || continue
		qsc_current_node_denied "$node" && continue
		qsc_current_node_blacklisted "$node" && continue
		first="$node"
		break
	done

	if [ -z "$first" ]; then
		if [ "$(cat "$DATADIR/current_mode_tag" 2>/dev/null)" != "无可用节点" ]; then
			echo "$(date +%F_%T) 电流控制：未配置 battery_current 且无安全节点，跳过写入" >>"$LOG_FILE"
			echo "无可用节点" >"$DATADIR/current_mode_tag"
		fi
		QSC_CURRENT_NODES=""
		return 1
	fi

	QSC_CURRENT_NODES=" $first"
	if qsc_current_is_mtk; then
		if [ "$(cat "$DATADIR/current_node_note" 2>/dev/null)" != "$first" ]; then
			echo "$(date +%F_%T) 电流控制(MTK)：自动选用单一节点 $first" >>"$LOG_FILE"
			echo "$first" >"$DATADIR/current_node_note"
		fi
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

qsc_current_write_target() {
	local target="$1"
	local node cur next wrote=0 after
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
		if [ "${QSC_CURRENT_FORCE:-0}" != "1" ]; then
			qsc_current_node_denied "$node" && continue
			qsc_current_node_blacklisted "$node" && continue
		fi

		chmod 0644 "$node" 2>/dev/null
		cur="$(cat "$node" 2>/dev/null | egrep -v '\-|\+' | tr -d ' \r\n')"
		case "$cur" in
			""|*[!0-9]*) continue ;;
		esac

		if [ "${QSC_CURRENT_FORCE:-0}" != "1" ]; then
			if ! qsc_current_value_plausible "$cur" "$target"; then
				qsc_current_blacklist_node "$node" "读回值不像µA上限(cur=$cur target=$target)"
				continue
			fi
		fi

		if [ "$cur" = "$target" ]; then
			continue
		fi

		# 高于目标则分步降流；否则（含抬流）直接落到目标
		if [ "$cur" -gt "$target" ]; then
			next=$((cur - 500000))
			if [ "$next" -gt "$target" ] && [ "$target" != "0" ]; then
				echo "$next" >"$node" 2>/dev/null || continue
			else
				echo "$target" >"$node" 2>/dev/null || continue
			fi
		else
			echo "$target" >"$node" 2>/dev/null || continue
		fi

		if [ "${QSC_CURRENT_FORCE:-0}" != "1" ]; then
			after="$(cat "$node" 2>/dev/null | egrep -v '\-|\+' | tr -d ' \r\n')"
			# 写后读回仍像档位 → 拉黑，避免每 3s 抢写
			if [ -n "$after" ]; then
				case "$after" in
					*[!0-9]*) ;;
					*)
						if [ "$after" -le 64 ] && [ "$target" -gt 1000 ]; then
							qsc_current_blacklist_node "$node" "写后读回仍像档位(after=$after)"
							continue
						fi
						;;
				esac
			fi
		fi
		wrote=1
	done
	[ "$wrote" = "1" ]
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
	local reason target now_c battery_stop_1
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

	# 同目标冷却：避免读回失败时每 3s 抢写
	reason="${mode_tag}:${target}"
	if [ "$(cat "$DATADIR/current_mode_tag" 2>/dev/null)" = "$reason" ]; then
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

	if qsc_current_write_target "$target"; then
		if [ "$(cat "$DATADIR/current_mode_tag" 2>/dev/null)" != "$reason" ]; then
			now_c="$(qsc_current_now_ua)"
			echo "$(date +%F_%T) 电量$battery_level ${mode_tag}：目标电流${target} 节点${QSC_CURRENT_NODES} 实时电流${now_c} 温度${temperature}" >>"$LOG_FILE"
			echo "$reason" >"$DATADIR/current_mode_tag"
		fi
		date +%s >"$DATADIR/current_write_ts" 2>/dev/null
	fi
}
