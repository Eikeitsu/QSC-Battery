#!/system/bin/sh
# 电流控制：模拟旁路 / 慢充 / 默认限流 / 温度阶梯 / 游戏限流
# 配置：config/current.json；总开关 current_control=0 时整段跳过。
# 写入策略：
# - 从 battery_current 读取节点列表，对本机存在的路径全部写入
# - 额外合并开机探测的 *restrict*_cur*（list_charge_current）
# - 限流前按 restricted 写入策略参数（如 qcom restrict_chg）
# - 统一「当前值-500000」步进；不读回校验、不拉黑；节点文件存在即记日志
# 安全约束：
# - 不写 /data/vendor/thermal；不做 MCA/内核补丁
# - 不写 charge_control_limit / thermal_input_current 等非电流策略节点

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

# current.json 变更时重置节点缓存与模式标记
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
		rm -f "${LIST_CHARGE_CURRENT:-$DATADIR/list_charge_current}"
		rm -f "$DATADIR/current_node_note" "$DATADIR/current_mode_tag" "$DATADIR/current_reached"
		echo "$(date +%F_%T) 电流控制：检测到 current.json 变更，已重置节点缓存" >>"$LOG_FILE"
	fi
	printf '%s\n' "$new" >"$meta_file"
}

# 扫描 *restrict*_cur*（排除 usb）写入 list_charge_current
qsc_current_refresh_restrict_list() {
	local list="${LIST_CHARGE_CURRENT:-$DATADIR/list_charge_current}"
	mkdir -p "$DATADIR" 2>/dev/null
	find /sys/ -name '*restrict*_cur*' 2>/dev/null \
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
		echo "$(date +%F_%T) 电流控制：写入节点 $(qsc_nodes_short "$QSC_CURRENT_NODES")" >>"$LOG_FILE"
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

# 写入电流目标：统一 cur-500000 步进；不读回、不拉黑
# 副作用：QSC_CW_HIT=1 表示至少有一个节点文件存在
#          QSC_CW_STEPPING=1 表示本轮写了中间台阶（尚未等于目标）
qsc_current_write_target() {
	local target="$1"
	local node cur next step_to hit=0 wrote_step=0
	QSC_CW_HIT=0
	QSC_CW_FROM=""
	QSC_CW_TO=""
	QSC_CW_REACHED=0
	QSC_CW_STEPPING=0
	case "$target" in
		""|*[!0-9]*) return 1 ;;
	esac
	# 非旁路目标下限 100000µA；旁路目标 0 保留
	if [ "$target" != "0" ] && [ "$target" -lt 100000 ]; then
		target=100000
	fi
	if [ "$target" -gt 10000000 ]; then
		target=10000000
	fi

	for node in $QSC_CURRENT_NODES; do
		[ -f "$node" ] || continue
		qsc_current_node_denied "$node" && continue

		hit=1
		chmod 0644 "$node" 2>/dev/null
		cur="$(cat "$node" 2>/dev/null | egrep -v '\-|\+' | tr -d ' \r\n')"
		case "$cur" in
			""|*[!0-9]*) continue ;;
		esac

		# 已是目标：跳过写入，仍计为「有节点」
		if [ "$cur" = "$target" ]; then
			QSC_CW_REACHED=1
			[ -z "$QSC_CW_FROM" ] && QSC_CW_FROM="$cur" && QSC_CW_TO="$cur"
			continue
		fi

		# 先算 cur-500000，若仍高于目标则写台阶，否则写目标
		next=$((cur - 500000))
		if [ "$next" -gt "$target" ]; then
			step_to="$next"
			wrote_step=1
		else
			step_to="$target"
		fi
		echo "$step_to" >"$node" 2>/dev/null || true

		if [ -z "$QSC_CW_FROM" ]; then
			QSC_CW_FROM="$cur"
			QSC_CW_TO="$step_to"
		fi
		if [ "$step_to" = "$target" ]; then
			QSC_CW_REACHED=1
		fi
	done

	QSC_CW_HIT="$hit"
	if [ "$wrote_step" = "1" ] && [ "${QSC_CW_REACHED:-0}" != "1" ]; then
		QSC_CW_STEPPING=1
	fi
	[ "$hit" = "1" ]
}

qsc_current_now_ua() {
	local c
	c="$(qsc_safe_cat /sys/class/power_supply/battery/current_now 2>/dev/null)"
	c="$(echo "$c" | sed 's/-//g' | tr -d ' \r\n')"
	echo "${c:-0}"
}

# 游戏命中：进程列表匹配主程序；并补充前台窗口匹配
qsc_current_game_hit() {
	local pkg focus list_file ps_line
	list_file="$DATADIR/.app_list_tmp"
	qsc_current_conf_get_strings app_list >"$list_file" 2>/dev/null || return 1
	[ -s "$list_file" ] || {
		rm -f "$list_file"
		return 1
	}

	while IFS= read -r pkg || [ -n "$pkg" ]; do
		pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
		[ -n "$pkg" ] || continue
		# ps 匹配包名，排除 pkg: 子进程与 egrep 自身
		ps_line="$(ps -ef 2>/dev/null | egrep "$pkg" | egrep -v "${pkg}:" | egrep -v 'egrep')"
		if [ -n "$ps_line" ]; then
			rm -f "$list_file"
			return 0
		fi
	done <"$list_file"

	# 补充：前台窗口包名命中也触发
	focus="$(dumpsys window 2>/dev/null | grep 'mCurrentFocus' | tail -1)"
	[ -z "$focus" ] && focus="$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1)"
	if [ -n "$focus" ]; then
		while IFS= read -r pkg || [ -n "$pkg" ]; do
			pkg="$(printf '%s' "$pkg" | tr -d ' \r\n')"
			[ -n "$pkg" ] || continue
			if echo "$focus" | grep -q "$pkg"; then
				rm -f "$list_file"
				return 0
			fi
		done <"$list_file"
	fi

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
# 优先级：旁路 > 二限/慢充/回补 > 游戏 > 一限 > 默认；可选旁路温度/时段、硬件旁路、高温保护
qsc_apply_current_control() {
	local enable battery_stop slow_charge temp_cur
	local limit1 limit2 cur1 cur2 def_max app_on app_cur
	local reason target now_c battery_stop_1 prev_tag
	local mode_tag="" log_name="" bypass_mode safety_temp bypass_temp
	local want_bypass=0 used_hw=0 by_level=0 by_temp=0 by_sched=0
	local reasons="" cpu_log=0 slow_charge_mode=0 under_stop1=1

	[ -f "$CURRENT_CONF" ] || return 0
	enable="$(qsc_current_conf_get current_control)"
	[ "$enable" = "1" ] || {
		qsc_bypass_hw_off
		return 0
	}

	qsc_current_build_nodes || return 0
	[ -n "$(echo "$QSC_CURRENT_NODES" | tr -d ' ')" ] || return 0

	# 限流前先写 restricted
	qsc_current_apply_restricted

	battery_stop="$(qsc_current_conf_get battery_stop)"
	bypass_temp="$(qsc_current_conf_get bypass_temp)"
	slow_charge="$(qsc_current_conf_get slow_charge)"
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

	battery_stop="$(qsc_clamp_level_or_off "$battery_stop" 110)"
	bypass_temp="$(qsc_clamp_level_or_off "$bypass_temp" 110)"
	slow_charge="$(qsc_clamp_level_or_off "$slow_charge" 110)"
	temp_cur="$(qsc_clamp_int "$temp_cur" 0 1 0)"
	app_on="$(qsc_clamp_int "$app_on" 0 1 0)"
	limit1="$(qsc_clamp_int "$limit1" 25 60 40)"
	limit2="$(qsc_clamp_int "$limit2" 25 60 45)"
	if [ "$limit2" -le "$limit1" ] 2>/dev/null; then
		limit2=$((limit1 + 5))
		[ "$limit2" -gt 60 ] && limit2=60
	fi
	def_max="$(qsc_clamp_int "$def_max" 100000 10000000 5000000)"
	cur1="$(qsc_clamp_int "$cur1" 100000 10000000 1500000)"
	cur2="$(qsc_clamp_int "$cur2" 100000 3000000 100000)"
	app_cur="$(qsc_clamp_int "$app_cur" 100000 3000000 200000)"
	# 层级：二限 ≤ 游戏 ≤ 一限 ≤ 默认
	[ "$cur1" -gt "$def_max" ] 2>/dev/null && cur1="$def_max"
	[ "$app_cur" -gt "$cur1" ] 2>/dev/null && app_cur="$cur1"
	[ "$cur2" -gt "$app_cur" ] 2>/dev/null && cur2="$app_cur"
	case "$bypass_mode" in
		auto) ;;
		*) bypass_mode="sim" ;;
	esac
	safety_temp="$(qsc_clamp_int "$safety_temp" 40 55 48)"

	battery_stop_1=$((battery_stop - 1))

	# 电流温控档位：2=二限，1=一限
	if [ "$temp_cur" = "1" ] && [ -n "$temperature" ]; then
		if [ "$temperature" -ge "$limit2" ]; then
			cpu_log=2
		elif [ "$temperature" -ge "$limit1" ]; then
			cpu_log=1
		fi
	fi

	# 旁路：电量 / 温度 / 时段（后两者默认关闭）
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
		mode_tag="模拟旁路"
		log_name="模拟旁路充电"
		[ "$reasons" != "电量" ] && [ -n "$reasons" ] && log_name="模拟旁路充电·${reasons}"
	fi

	# 慢充：电量>=slow 且不等于旁路回补点
	if [ "$want_bypass" != "1" ] && [ "$slow_charge" -le 100 ] && [ -n "$battery_level" ] \
		&& [ "$battery_level" != "$battery_stop_1" ] && [ "$battery_level" -ge "$slow_charge" ]; then
		slow_charge_mode=1
	fi

	# 电量 >= stop-1 时走回补小电流，不走游戏/默认（stop=110 关闭旁路时不启用此门槛）
	if [ "$battery_stop" -le 100 ] && [ -n "$battery_level" ] && [ "$battery_level" -ge "$battery_stop_1" ]; then
		under_stop1=0
	fi

	if [ "$want_bypass" != "1" ]; then
		# 旁路回补(stop-1) / 二限温控 / 慢充 → 二限电流
		if [ "$cpu_log" = "2" ] || [ "$slow_charge_mode" = "1" ] \
			|| { [ "$battery_stop" -le 100 ] && [ "$battery_level" = "$battery_stop_1" ]; }; then
			target="$cur2"
			if [ "$cpu_log" = "2" ]; then
				mode_tag="二限温控"
				log_name="触发二限电流温控"
			elif [ "$slow_charge_mode" = "1" ]; then
				mode_tag="慢充"
				log_name="慢充模式"
			else
				mode_tag="旁路回补"
				log_name="模拟旁路充电"
			fi
		elif [ "$under_stop1" = "1" ]; then
			if [ "$app_on" = "1" ] && qsc_current_game_hit; then
				target="$app_cur"
				mode_tag="游戏限流"
				log_name="游戏模式"
			elif [ "$cpu_log" = "1" ]; then
				target="$cur1"
				mode_tag="一限温控"
				log_name="触发一限电流温控"
			else
				target="$def_max"
				mode_tag="默认限流"
				log_name="默认模式"
			fi
		else
			# 兜底默认
			target="$def_max"
			mode_tag="默认限流"
			log_name="默认模式"
		fi
	fi

	# 高温保护（扩展）：旁路时不写 0
	if [ "$want_bypass" = "1" ] && [ -n "$temperature" ] && [ "$temperature" -ge "$safety_temp" ]; then
		want_bypass=0
		target="$cur2"
		mode_tag="高温保护"
		log_name="高温保护"
		qsc_bypass_hw_off
	fi

	# 硬件旁路（扩展，bypass_mode=auto）
	if [ "$want_bypass" = "1" ] && [ "$bypass_mode" = "auto" ]; then
		if qsc_bypass_probe_node && qsc_bypass_hw_on "$QSC_BYPASS_NODE"; then
			used_hw=1
			mode_tag="节点旁路"
			log_name="节点旁路"
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
			echo "$(date +%F_%T) 电量$battery_level ${log_name}：节点$QSC_BYPASS_NODE 实时电流${now_c} 温度${temperature}" >>"$LOG_FILE"
			echo "$reason" >"$DATADIR/current_mode_tag"
		fi
		return 0
	fi

	# 每轮写入；步进未到目标时同样继续
	reason="${mode_tag}:${target}"
	prev_tag="$(cat "$DATADIR/current_mode_tag" 2>/dev/null)"

	if ! qsc_current_write_target "$target"; then
		if [ "$prev_tag" != "none:$reason" ]; then
			echo "$(date +%F_%T) 电量$battery_level 电流控制无可用节点：${log_name} 目标$(qsc_fmt_ma "$target")" >>"$LOG_FILE"
			echo "none:$reason" >"$DATADIR/current_mode_tag"
		fi
		return 0
	fi

	now_c="$(qsc_current_now_ua)"
	# 同模式只在切换或步进时记一行，避免刷屏（写入仍每轮执行）
	if [ "$prev_tag" != "$reason" ] || [ "${QSC_CW_STEPPING:-0}" = "1" ]; then
		echo "$(date +%F_%T) 电量$battery_level ${log_name}：限制电流${target} 实时电流${now_c} 温度${temperature}" >>"$LOG_FILE"
	fi
	echo "$reason" >"$DATADIR/current_mode_tag"
	if [ "${QSC_CW_STEPPING:-0}" = "1" ]; then
		echo 0 >"$DATADIR/current_reached"
	else
		echo 1 >"$DATADIR/current_reached"
	fi
	date +%s >"$DATADIR/current_write_ts" 2>/dev/null
}
