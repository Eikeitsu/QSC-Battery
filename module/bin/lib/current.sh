#!/system/bin/sh
# 电流控制：模拟旁路 / 慢充 / 默认限流 / 温度阶梯 / 游戏限流
# 配置：config/current.jsonc；总开关 current_control=0 时整段跳过。
# 安全约束：不写 /data/vendor/thermal；不做 MCA/内核补丁；硬件旁路节点仅在存在且可读写时选用。

# JSONC 解析
[ -n "$QSC_JSONC_LOADED" ] || {
	if [ -f "${LIBDIR:-}/jsonc.sh" ]; then
		. "$LIBDIR/jsonc.sh"
	elif [ -f "${0%/*}/jsonc.sh" ]; then
		. "${0%/*}/jsonc.sh"
	fi
	QSC_JSONC_LOADED=1
}

QSC_CURRENT_FALLBACK="\
/sys/class/power_supply/battery/constant_charge_current_max \
/sys/class/power_supply/battery/constant_charge_current \
/sys/class/power_supply/battery/fast_charge_current \
/sys/class/power_supply/battery/fast_charge_current_max \
/sys/class/power_supply/battery/thermal_input_current \
/sys/class/power_supply/battery/current_max \
/sys/class/power_supply/battery/input_current_max \
/sys/class/power_supply/battery/charge_current \
/sys/class/power_supply/battery/charge_control_limit"

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

qsc_current_build_nodes() {
	local node
	QSC_CURRENT_NODES=""
	# 优先读 battery_current 字符串数组
	qsc_current_conf_get_strings battery_current >"$DATADIR/.current_nodes_tmp" 2>/dev/null || : >"$DATADIR/.current_nodes_tmp"
	while IFS= read -r node || [ -n "$node" ]; do
		case "$node" in
			/sys/*|/proc/*)
				[ -f "$node" ] && QSC_CURRENT_NODES="$QSC_CURRENT_NODES $node"
				;;
		esac
	done <"$DATADIR/.current_nodes_tmp"
	rm -f "$DATADIR/.current_nodes_tmp"
	if [ -z "$(echo "$QSC_CURRENT_NODES" | tr -d ' ')" ]; then
		for node in $QSC_CURRENT_FALLBACK; do
			[ -f "$node" ] && QSC_CURRENT_NODES="$QSC_CURRENT_NODES $node"
		done
	fi
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

qsc_current_write_target() {
	local target="$1"
	local node cur next wrote=0
	case "$target" in
		""|*[!0-9]*) return 1 ;;
	esac
	# 非旁路目标时避免过小电流（保留模拟旁路的 0）
	if [ "$target" != "0" ] && [ "$target" -lt 50000 ]; then
		target=50000
	fi
	for node in $QSC_CURRENT_NODES; do
		[ -f "$node" ] || continue
		chmod 0644 "$node" 2>/dev/null
		cur="$(cat "$node" 2>/dev/null | egrep -v '\-|\+' | tr -d ' \r\n')"
		case "$cur" in
			""|*[!0-9]*) continue ;;
		esac
		if [ "$cur" = "$target" ]; then
			continue
		fi
		# 降流时分步，减轻充电 IC 突变压力
		if [ "$cur" -gt "$target" ]; then
			next=$((cur - 500000))
			if [ "$next" -gt "$target" ] && [ "$target" != "0" ]; then
				echo "$next" >"$node" 2>/dev/null
			else
				echo "$target" >"$node" 2>/dev/null
			fi
		else
			echo "$target" >"$node" 2>/dev/null
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

# 依赖外部环境：battery_level temperature；且未触发供电开关停充
qsc_apply_current_control() {
	local enable battery_stop slow_charge temp_cur
	local limit1 limit2 cur1 cur2 def_max app_on app_cur
	local reason target now_c battery_stop_1
	local mode_tag="" bypass_mode safety_temp want_bypass=0 used_hw=0

	[ -f "$CURRENT_CONF" ] || return 0
	enable="$(qsc_current_conf_get current_control)"
	[ "$enable" = "1" ] || {
		qsc_bypass_hw_off
		return 0
	}

	qsc_current_build_nodes
	[ -n "$(echo "$QSC_CURRENT_NODES" | tr -d ' ')" ] || return 0

	battery_stop="$(qsc_current_conf_get battery_stop)"
	[ -z "$battery_stop" ] && battery_stop=110
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

	# 优先级：模拟旁路 > 二限/旁路回补/慢充 > 游戏限流 > 一限 > 默认
	if [ "$battery_stop" -le 100 ] && [ "$battery_level" -ge "$battery_stop" ]; then
		want_bypass=1
		target=0
		mode_tag="模拟旁路"
	else
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

	if qsc_current_write_target "$target"; then
		reason="${mode_tag}:${target}"
		if [ "$(cat "$DATADIR/current_mode_tag" 2>/dev/null)" != "$reason" ]; then
			now_c="$(qsc_current_now_ua)"
			echo "$(date +%F_%T) 电量$battery_level ${mode_tag}：目标电流${target} 实时电流${now_c} 温度${temperature}" >>"$LOG_FILE"
			echo "$reason" >"$DATADIR/current_mode_tag"
		fi
	fi
}
