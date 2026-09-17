#!/system/bin/sh
# current: probe / limits / node build
# 电流控制：模拟旁路 / 慢充 / 默认限流 / 温度阶梯 / 游戏限流
# 配置：config/current.json；总开关 current_control=0 时整段跳过。
# 写入策略（省 I/O / 省电）：
# - 主路径：对各 power_supply/*/constant_charge_current_max 写微安目标（mA×1000）
# - 补充：电池/main 其它上限、restrict*_cur*；不写 usb/qc_usb 等输入口节点
# - 实测电流已不高于目标+裕量：跳过节点巡检与周期重申（偏小不强制）
# - 偏高：优先漂移强制（连续 2 轮）；到期周期重申仅在偏高时触发（默认约 24s）
# - 读回已等于目标则跳过 echo；强制时只轻写工作节点、试 1 次
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

# 配置缺失时的兜底路径（探测失败时的补充，仍须本机存在）
QSC_CURRENT_SAFE_FALLBACK="\
/sys/class/power_supply/main/constant_charge_current_max \
/sys/class/power_supply/battery/constant_charge_current_max \
/sys/class/power_supply/battery/constant_charge_current \
/sys/class/power_supply/battery/fast_charge_current \
/sys/class/power_supply/battery/current_max"

# 可选硬件旁路节点（仅探测，不强制创建）
# 正极性：写 1 进入旁路（充电器直供主板，电池休眠）
QSC_BYPASS_NODE_CANDIDATES="\
/sys/class/qcom-battery/bypass_charging_enable \
/sys/class/power_supply/main/bypass_enable \
/sys/class/power_supply/battery/enable_bypass_mode \
/sys/class/power_supply/battery/bypass_charging"
# 反极性候选已移除：OPlus mmi_charging_enable 实为充电使能节点，
# 自动探测当旁路会误把「关充电」当成旁路，存在硬停充风险。
# 若确需使用，请在 power_switch / 自定义旁路路径中显式配置。
QSC_BYPASS_INV_CANDIDATES=""

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
	# 不写 USB 等输入口电流节点（仅用 online 判断插电）
	case "$node" in
		*/power_supply/usb/*|*/power_supply/qc_usb/*|*/power_supply/pc_port/*| \
		*/power_supply/dc/*|*/power_supply/wireless/*|*/power_supply/usb_pd/*)
			return 0
			;;
	esac
	base="${node##*/}"
	for deny in $QSC_CURRENT_DENY; do
		[ "$base" = "$deny" ] && return 0
	done
	return 1
}

qsc_current_usleep() {
	if command -v usleep >/dev/null 2>&1; then
		usleep 330000 2>/dev/null || sleep 1
	else
		sleep 1
	fi
}

# 是否在充电（与 list_curr 一致）
qsc_current_is_charging() {
	local st
	st="$(cat /sys/class/power_supply/battery/status 2>/dev/null | tr -d ' \r\n')"
	case "$st" in
		Charging|Full|Quick\ Charge*|Fast\ Charging*) return 0 ;;
	esac
	st="$(cat /sys/class/power_supply/usb/online 2>/dev/null | tr -d ' \r\n')"
	[ "$st" = "1" ] && return 0
	return 1
}

# 触发电流节点探测（外部脚本）
qsc_current_probe_ctrl_files() {
	local script="${BINDIR:-}/list_current.sh"
	[ -f "$script" ] || return 1
	chmod 0755 "$script" 2>/dev/null
	"$script" >/dev/null 2>&1
}

# 首次限流前：放开主路径上限节点写权限（跳过 usb 等输入口）
qsc_current_prepare_once() {
	local f
	[ -f "$DATADIR/current_prep_done" ] && return 0
	for f in /sys/class/power_supply/*/constant_charge_current_max \
		/sys/class/power_supply/main/constant_charge_current_max \
		/sys/class/power_supply/battery/constant_charge_current_max \
		/sys/class/power_supply/battery/constant_charge_current \
		/sys/class/power_supply/main/constant_charge_current; do
		[ -f "$f" ] || continue
		qsc_current_node_denied "$f" && continue
		chown 0:0 "$f" 2>/dev/null
		chmod 0664 "$f" 2>/dev/null
	done
	date +%s >"$DATADIR/current_prep_done" 2>/dev/null
	return 0
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
		rm -f "${CH_CURR_WORKING:-$DATADIR/ch_curr_working}"
		rm -f "$DATADIR/.ch_curr_session_fail" "$DATADIR/current_prep_done"
		rm -f "$DATADIR/current_node_note" "$DATADIR/current_mode_tag" "$DATADIR/current_reached"
		rm -f "$DATADIR/current_reaffirm_ts" "$DATADIR/current_drift_streak"
		qsc_log debug "电流控制：检测到 current.json 变更，已重置节点缓存"
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

# QSC_CURR_ENTRIES：空格分隔 path::scale
qsc_current_add_entry() {
	local path="$1" scale="$2"
	path="$(printf '%s' "$path" | tr -d ' \r\n')"
	scale="$(printf '%s' "$scale" | tr -d ' \r\n')"
	[ -n "$path" ] && [ -f "$path" ] || return 1
	qsc_current_node_denied "$path" && return 1
	case "$scale" in
		1|1000) ;;
		*) scale=1 ;;
	esac
	case " $QSC_CURR_ENTRIES " in
		*" $path::"*) return 0 ;;
	esac
	QSC_CURR_ENTRIES="$QSC_CURR_ENTRIES $path::$scale"
	return 0
}

qsc_current_load_ctrl_file() {
	local list="${CH_CURR_CTRL_FILES:-$DATADIR/ch_curr_ctrl_files}"
	local line path scale rest
	[ -f "$list" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		line="$(printf '%s' "$line" | tr -d ' \r\n')"
		[ -n "$line" ] || continue
		case "$line" in
			*::*::*)
				path="${line%%::*}"
				rest="${line#*::}"
				scale="${rest%%::*}"
				qsc_current_add_entry "$path" "$scale"
				;;
		esac
	done <"$list"
	return 0
}

qsc_current_add_path_guess_scale() {
	local path="$1" cur
	[ -f "$path" ] || return 1
	qsc_current_node_denied "$path" && return 1
	cur="$(cat "$path" 2>/dev/null | tr -d ' \r\n')"
	case "$cur" in
		""|-*|[01]|*[!0-9]*)
			qsc_current_add_entry "$path" 1
			return 0
			;;
	esac
	if [ "$cur" -lt 10000 ] 2>/dev/null; then
		qsc_current_add_entry "$path" 1000
	else
		qsc_current_add_entry "$path" 1
	fi
}

qsc_current_append_existing_paths() {
	local list_file="$1" node
	[ -f "$list_file" ] || return 0
	while IFS= read -r node || [ -n "$node" ]; do
		node="$(echo "$node" | tr -d ' \r\n')"
		case "$node" in
			/sys/*|/proc/*)
				qsc_current_add_path_guess_scale "$node" || true
				;;
		esac
	done <"$list_file"
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

# 构建运行时节点表 QSC_CURR_ENTRIES；兼容导出 QSC_CURRENT_NODES（仅 path）
qsc_current_build_nodes() {
	local node note="" path scale working="$DATADIR/ch_curr_working"
	local ctrl="${CH_CURR_CTRL_FILES:-$DATADIR/ch_curr_ctrl_files}"
	local list e ordered rest w
	QSC_CURR_ENTRIES=""
	QSC_CURRENT_NODES=""

	qsc_current_sync_conf_guard

	# 空探测列表且在充 → 触发探测
	if [ ! -s "$ctrl" ] && qsc_current_is_charging; then
		qsc_current_probe_ctrl_files
	fi

	# 1) 自动探测结果优先
	qsc_current_load_ctrl_file

	# 2) 用户补充 battery_current
	qsc_current_conf_get_strings battery_current >"$DATADIR/.current_nodes_tmp" 2>/dev/null || : >"$DATADIR/.current_nodes_tmp"
	if [ -s "$DATADIR/.current_nodes_tmp" ]; then
		qsc_current_append_existing_paths "$DATADIR/.current_nodes_tmp"
	fi
	rm -f "$DATADIR/.current_nodes_tmp"

	# 3) 仍空：兜底四路径
	if [ -z "$(echo "$QSC_CURR_ENTRIES" | tr -d ' ')" ]; then
		for node in $QSC_CURRENT_SAFE_FALLBACK; do
			qsc_current_add_path_guess_scale "$node" || true
		done
	fi

	# 4) restrict*_cur*
	list="${LIST_CHARGE_CURRENT:-$DATADIR/list_charge_current}"
	[ -f "$list" ] || qsc_current_refresh_restrict_list
	[ -f "$list" ] && qsc_current_append_existing_paths "$list"

	# constant_charge_current_max 优先（含 main/battery）
	if [ -n "$(echo "$QSC_CURR_ENTRIES" | tr -d ' ')" ]; then
		ordered=""
		rest=""
		for e in $QSC_CURR_ENTRIES; do
			path="${e%%::*}"
			case "$path" in
				*/constant_charge_current_max) ordered="$ordered $e" ;;
				*) rest="$rest $e" ;;
			esac
		done
		QSC_CURR_ENTRIES="$ordered $rest"
	fi

	# 有效节点优先：working 中的条目挪到前面
	if [ -s "$working" ] && [ -n "$(echo "$QSC_CURR_ENTRIES" | tr -d ' ')" ]; then
		ordered=""
		rest="$QSC_CURR_ENTRIES"
		while IFS= read -r w || [ -n "$w" ]; do
			w="$(printf '%s' "$w" | tr -d ' \r\n')"
			[ -n "$w" ] || continue
			case " $rest " in
				*" $w "*) ordered="$ordered $w" ;;
			esac
		done <"$working"
		for e in $rest; do
			case " $ordered " in
				*" $e "*) ;;
				*) ordered="$ordered $e" ;;
			esac
		done
		QSC_CURR_ENTRIES="$ordered"
	fi

	for e in $QSC_CURR_ENTRIES; do
		path="${e%%::*}"
		[ -n "$path" ] || continue
		QSC_CURRENT_NODES="$QSC_CURRENT_NODES $path"
	done

	if [ -z "$(echo "$QSC_CURR_ENTRIES" | tr -d ' ')" ]; then
		if [ "$(cat "$DATADIR/current_mode_tag" 2>/dev/null)" != "无可用节点" ]; then
			qsc_log error "电流控制：无可用电流节点（请插电后让模块探测）"
			echo "无可用节点" >"$DATADIR/current_mode_tag"
		fi
		return 1
	fi

	note="entries:$QSC_CURR_ENTRIES"
	if [ "$(cat "$DATADIR/current_node_note" 2>/dev/null)" != "$note" ]; then
		qsc_log debug "电流控制：写入节点 $(qsc_nodes_short "$QSC_CURRENT_NODES")"
		echo "$note" >"$DATADIR/current_node_note"
	fi
	return 0
}

# 探测可用硬件旁路节点；写入 QSC_BYPASS_NODE / QSC_BYPASS_ON_VAL（可能为空）
# 正极性节点写 1 进旁路；反极性节点写 0 进旁路
