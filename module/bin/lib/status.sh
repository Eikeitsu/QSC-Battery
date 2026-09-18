#!/system/bin/sh
# 模块简介动态文案
# 格式：[大状态 | 子状态] 括号外说明
# emoji 后无空格；方括号内 | 两侧加空格；子状态分隔统一用 ●（两侧加空格）

DESC_INTRO="电量/温度停充；电流控制为安装时可选。配置：config/config.conf，日志：data/log.log。"
# 关闭动态简介时的专用固定文案（不用「启动中」等动态默认句）
DESC_STATIC="电量/温度停充；电流控制为安装时可选。配置：config/config.conf，日志：data/log.log。"

# description_enable：1=动态简介（默认）；0=写入 DESC_STATIC 固定文案，停 worker，少写盘。
qsc_description_enabled() {
	local v
	v="${description_enable:-${QSCV_description_enable:-}}"
	if [ -z "$v" ] && [ -n "${CONFDIR:-}" ] && [ -f "$CONFDIR/config.conf" ]; then
		v="$(sed -n 's/^description_enable=//p' "$CONFDIR/config.conf" 2>/dev/null | head -n1 | tr -d ' \r')"
	fi
	case "$v" in
		0) return 1 ;;
		*) return 0 ;;
	esac
}

qsc_description_restore_static() {
	# 只改 description=，不动 version 等其它字段
	type qsc_write_module_description >/dev/null 2>&1 || return 0
	qsc_write_module_description "充电控制" "" "${DESC_STATIC:-$DESC_INTRO}"
}

# $1=大状态  $2=括号内子状态（可空）  $3=括号外说明（必填，可空则回退 DESC_INTRO）
# 结果写入 QSC_DESC 而不是 echo：本函数每轮都会被调用，命令替换会白 fork 一次
qsc_format_module_description() {
	local major="$1"
	local inner="$2"
	local outer="$3"

	if [ -n "$inner" ]; then
		QSC_DESC="[${major} | ${inner}]"
	else
		QSC_DESC="[${major}]"
	fi
	[ -n "$outer" ] || outer="$DESC_INTRO"
	QSC_DESC="${QSC_DESC} ${outer}"
}

qsc_description_lock_acquire() {
	local lock="$DATADIR/.description.lock"
	local owner i
	i=0
	while ! mkdir "$lock" 2>/dev/null; do
		owner="$(cat "$lock/pid" 2>/dev/null | tr -d ' \r\n')"
		case "$owner" in
			""|*[!0-9]*) rm -rf "$lock" 2>/dev/null ;;
			*) kill -0 "$owner" 2>/dev/null || rm -rf "$lock" 2>/dev/null ;;
		esac
		i=$((i + 1))
		[ "$i" -ge 5 ] && return 1
		sleep 1
	done
	printf '%s\n' "$$" >"$lock/pid" 2>/dev/null || {
		rm -rf "$lock" 2>/dev/null
		return 1
	}
	return 0
}

qsc_description_lock_release() {
	local lock="$DATADIR/.description.lock" owner
	owner="$(cat "$lock/pid" 2>/dev/null | tr -d ' \r\n')"
	[ "$owner" = "$$" ] && rm -rf "$lock" 2>/dev/null
}

qsc_write_module_description() {
	local major="$1"
	local inner="$2"
	local outer="$3"
	local prop desc old tmp line found

	prop="$MODDIR/module.prop"
	[ -f "$prop" ] || return 0
	qsc_format_module_description "$major" "$inner" "$outer"
	desc="$QSC_DESC"
	qsc_description_lock_acquire || return 1
	# 取旧值用内建遍历：文案绝大多数时候没变，不值得为一次比对 fork grep+sed
	old=""
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			description=*) old="${line#description=}"; break ;;
		esac
	done <"$prop"
	if [ "$old" = "$desc" ]; then
		qsc_description_lock_release
		return 0
	fi

	tmp="$prop.tmp.$$"
	found=0
	if ! : >"$tmp"; then
		rm -f "$tmp" 2>/dev/null
		qsc_description_lock_release
		return 1
	fi
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			description=*)
				if [ "$found" = "0" ]; then
					printf '%s\n' "description=$desc" >>"$tmp" || {
						rm -f "$tmp" 2>/dev/null
						qsc_description_lock_release
						return 1
					}
					found=1
				fi
				;;
			*)
				printf '%s\n' "$line" >>"$tmp" || {
					rm -f "$tmp" 2>/dev/null
					qsc_description_lock_release
					return 1
				}
				;;
		esac
	done <"$prop"
	if [ "$found" = "0" ]; then
		printf '%s\n' "description=$desc" >>"$tmp" || {
			rm -f "$tmp" 2>/dev/null
			qsc_description_lock_release
			return 1
		}
	fi
	if ! mv -f "$tmp" "$prop" 2>/dev/null; then
		rm -f "$tmp" 2>/dev/null
		qsc_description_lock_release
		return 1
	fi
	if ! chmod 0644 "$prop" 2>/dev/null; then
		qsc_description_lock_release
		return 1
	fi
	qsc_description_lock_release
	return 0
}

# 根据运行标志刷新简介。依赖 qsc_switch 已算出的变量（可缺省）。
# 可选环境：module_off battery_level temperature battery_powered
#           full_log current_mode_tag（或读 data/current_mode_tag）
qsc_refresh_module_description() {
	local level temp major inner outer
	local cur_tag cur_mode stop_bits

	if ! qsc_description_enabled; then
		qsc_description_restore_static
		return 0
	fi

	level="${battery_level:-}"
	temp="${temperature:-}"

	# 还原失败排在最前面：此时充电节点仍停在停充值上，手机充不进电，
	# 是所有状态里最紧急的一个。尤其不能被下面「已关闭」那条提前 return 掉——
	# 关模块时还原失败恰恰是最容易让人找不到原因的情形。
	if [ -f "$DATADIR/resume_fail_hint" ]; then
		qsc_write_module_description "❗异常" "恢复充电失败" \
			"充电节点仍停在停充值，手机可能充不进电：请拔插一次充电器，或查看 data/log.log"
		return 0
	fi

	if [ -f "$MODDIR/disable" ] || [ "${module_off:-0}" = "1" ] || [ -f "$MODULE_OFF_FLAG" ]; then
		qsc_write_module_description "⛔已关闭" "模块未运行" \
			"打开总开关或移除 disable 后恢复电量/温度停充"
		return 0
	fi

	if [ ! -f "$BINDIR/qsc_switch.sh" ]; then
		qsc_write_module_description "❗异常" "核心脚本丢失" \
			"请重新安装模块并重启"
		return 0
	fi

	if [ ! -f "$LIST_SWITCH" ] && [ ! -f "$BINDIR/list_switch.sh" ]; then
		qsc_write_module_description "❗异常" "缺少开关列表" \
			"请重新安装模块并重启"
		return 0
	fi

	if [ -f "$DATADIR/no_battery_logged" ] && [ -z "$level" ]; then
		qsc_write_module_description "❗异常" "无法读取电量" \
			"dumpsys 与 sysfs 均失败，请查看 data/log.log"
		return 0
	fi

	if [ -f "$DATADIR/no_temp_logged" ] && [ -z "$temp" ]; then
		qsc_write_module_description "❗异常" "无法读取温度" \
			"dumpsys 与 sysfs 均失败，请查看 data/log.log"
		return 0
	fi

	if [ -f "$DATADIR/no_node_logged" ] && [ ! -f "$DATADIR/power_switch" ]; then
		qsc_write_module_description "❗异常" "停充节点无效" \
			"请插电后 Action 音量下测开关，或删除 data/list_switch 后重启重扫"
		return 0
	fi

	if [ -f "$DATADIR/stop_fail_hint" ] && [ ! -f "$DATADIR/power_switch" ]; then
		qsc_write_module_description "⚠️提示" "停充可能未生效" \
			"节点写入后仍在充电：请插电测开关，或删 data/list_switch 与 device.profile 后重启"
		return 0
	fi

	# 已停充：区分原因
	if [ -f "$DATADIR/power_switch" ]; then
		stop_bits=""
		[ -f "$DATADIR/battery_switch" ] && stop_bits="电量"
		if [ -f "$DATADIR/temp_switch" ]; then
			if [ -n "$stop_bits" ]; then
				stop_bits="${stop_bits}+温度"
			else
				stop_bits="温度"
			fi
		fi
		[ -z "$stop_bits" ] && stop_bits="停充中"

		if [ -n "$level" ] && [ -n "$temp" ]; then
			inner="${stop_bits} ● ${level}% ● ${temp}°C"
		elif [ -n "$level" ]; then
			inner="${stop_bits} ● ${level}%"
		else
			inner="$stop_bits"
		fi

		outer="已停止向电池充电，等待恢复条件"
		if [ -f "$DATADIR/battery_switch" ] && [ -n "$power_start" ]; then
			outer="电量降至 ${power_start}% 后恢复"
		fi
		if [ -f "$DATADIR/temp_switch" ] && [ -n "$temperature_switch_start" ]; then
			if [ -f "$DATADIR/battery_switch" ]; then
				outer="电量≤${power_start}% 且温度≤${temperature_switch_start}°C 后恢复"
			else
				outer="温度降至 ${temperature_switch_start}°C 后恢复"
			fi
		fi
		qsc_write_module_description "⏸️已停充" "$inner" "$outer"
		return 0
	fi

	# 充满再停等待中
	if [ "${full_log:-0}" = "1" ]; then
		inner="电量100%"
		[ -n "$temp" ] && inner="${inner} ● ${temp}°C"
		qsc_write_module_description "🔋充满再停" "$inner" \
			"等待涓流结束后再停充"
		return 0
	fi

	# 未插电
	if [ -z "${battery_powered:-}" ]; then
		if [ -n "$level" ] && [ -n "$temp" ]; then
			inner="${level}% ● ${temp}°C"
		elif [ -n "$level" ]; then
			inner="${level}%"
		else
			inner="等待插电"
		fi
		qsc_write_module_description "🔌未充电" "$inner" \
			"插入充电器后按阈值自动停充/恢复"
		return 0
	fi

	# 充电/供电中：按真实 status 区分，避免 MCA「插电 Not charging」也写「充电中」
	cur_tag="$(cat "$DATADIR/current_mode_tag" 2>/dev/null)"
	[ -z "$cur_tag" ] && cur_tag="${current_mode_tag:-}"
	cur_mode="${cur_tag%%:*}"

	if [ -n "$level" ] && [ -n "$temp" ]; then
		inner="${level}% ● ${temp}°C"
	elif [ -n "$level" ]; then
		inner="${level}%"
	else
		inner="供电中"
	fi

	# tr 已去掉空白：用 Notcharging 等形式匹配，勿再写 "Not charging"（SC2221/2222）
	_st="$(printf '%s' "${battery_status:-${QSC_BATTERY_STATUS:-}}" | tr -d ' \r\n')"
	_major="⚡充电中"
	case "$_st" in
		4|Notcharging|not_charging|NotCharging) _major="🔌供电中" ;;
		5|Full|full) _major="🔋已充满" ;;
		3|Discharging|discharging) _major="🔌已插电" ;;
		2|Charging|charging) _major="⚡充电中" ;;
	esac

	case "$cur_mode" in
		模拟旁路)
			qsc_write_module_description "📉模拟旁路" "$inner" \
				"充电电流压至约 0，接近旁路供电效果"
			;;
		节点旁路)
			qsc_write_module_description "⚙️节点旁路" "$inner" \
				"已使用本机旁路节点；无温控文件改动"
			;;
		高温保护)
			qsc_write_module_description "🌡️高温保护" "$inner" \
				"温度过高，已改用小电流而非强行旁路"
			;;
		慢充)
			qsc_write_module_description "🐢慢充中" "$inner" \
				"已切换二限小电流，减速补电"
			;;
		旁路回补)
			qsc_write_module_description "🔄旁路回补" "$inner" \
				"电量刚低于旁路阈值，小电流回补"
			;;
		游戏限流)
			qsc_write_module_description "🎮游戏限流" "$inner" \
				"前台游戏命中列表，已限制充电电流"
			;;
		一限温控)
			qsc_write_module_description "🌤️一限温控" "$inner" \
				"温度达到一限，已降低充电电流"
			;;
		二限温控)
			qsc_write_module_description "🔥二限温控" "$inner" \
				"温度达到二限，已切至更小电流"
			;;
		默认限流)
			qsc_write_module_description "$_major" "$inner" \
				"电流控制已开启，按默认上限限流"
			;;
		*)
			outer="按配置监控电量/温度阈值"
			if [ -n "$power_stop" ] && [ "$power_stop" -le 100 ] 2>/dev/null; then
				outer="电量≥${power_stop}% 将停充"
				if [ "${temperature_switch:-0}" = "1" ] && [ -n "$temperature_switch_stop" ]; then
					outer="电量≥${power_stop}% 或温度≥${temperature_switch_stop}°C 将停充"
				fi
			elif [ "${temperature_switch:-0}" = "1" ] && [ -n "$temperature_switch_stop" ]; then
				outer="温度≥${temperature_switch_stop}°C 将停充"
			fi
			qsc_write_module_description "$_major" "$inner" "$outer"
			;;
	esac
}
