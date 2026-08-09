#!/system/bin/sh
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
	local script="${BINDIR:-}/list_curr.sh"
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
			echo "$(date +%F_%T) 电流控制：无可用电流节点（请插电后让模块探测）" >>"$LOG_FILE"
			echo "无可用节点" >"$DATADIR/current_mode_tag"
		fi
		return 1
	fi

	note="entries:$QSC_CURR_ENTRIES"
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

# 是否需要强制重申 / 可否整轮跳过写节点
# $1=目标 µA
# 副作用：QSC_CW_FORCE / QSC_CW_FORCE_REASON / QSC_CW_NOW_UA / QSC_CW_OVER / QSC_CW_SKIP_IO
qsc_current_decide_force() {
	local target_ua="$1" ts last interval margin now_ua streak thr
	QSC_CW_FORCE=0
	QSC_CW_FORCE_REASON=""
	QSC_CW_NOW_UA=0
	QSC_CW_OVER=0
	QSC_CW_SKIP_IO=0

	case "$target_ua" in
		""|*[!0-9]*) return 0 ;;
	esac

	margin="$(qsc_current_conf_get current_drift_ua 2>/dev/null)"
	case "$margin" in
		""|*[!0-9]*) margin=300000 ;;
	esac
	[ "$margin" -lt 100000 ] 2>/dev/null && margin=100000
	[ "$margin" -gt 2000000 ] 2>/dev/null && margin=2000000

	now_ua="$(qsc_current_now_ua)"
	case "$now_ua" in
		""|*[!0-9]*) now_ua=0 ;;
	esac
	QSC_CW_NOW_UA="$now_ua"

	# 偏高阈值：目标>0 用 目标+裕量；旁路目标 0 用裕量本身
	if [ "$target_ua" -gt 0 ] 2>/dev/null; then
		thr=$((target_ua + margin))
	else
		thr="$margin"
	fi
	if [ "$now_ua" -gt "$thr" ] 2>/dev/null; then
		QSC_CW_OVER=1
	fi

	if [ "$QSC_CW_OVER" = "1" ]; then
		streak="$(cat "$DATADIR/current_drift_streak" 2>/dev/null | tr -d ' \r\n')"
		case "$streak" in
			""|*[!0-9]*) streak=0 ;;
		esac
		streak=$((streak + 1))
		echo "$streak" >"$DATADIR/current_drift_streak" 2>/dev/null
		# 连续 2 轮偏高 → 漂移强制（防读回撒谎）
		if [ "$streak" -ge 2 ]; then
			QSC_CW_FORCE=1
			QSC_CW_FORCE_REASON="drift"
		fi
	else
		# 偏小 / 正常：清漂移计数，绝不因偏低强制
		echo 0 >"$DATADIR/current_drift_streak" 2>/dev/null
	fi

	# 周期重申：默认 24s；仅在偏高时强制；偏低则推进时钟并跳过
	interval="$(qsc_current_conf_get current_reaffirm_sec 2>/dev/null)"
	case "$interval" in
		"" ) interval=24 ;;
		*[!0-9]*) interval=24 ;;
	esac
	if [ "$interval" != "0" ]; then
		[ "$interval" -lt 8 ] 2>/dev/null && interval=8
		[ "$interval" -gt 120 ] 2>/dev/null && interval=120
		ts="$(date +%s 2>/dev/null)"
		last="$(cat "$DATADIR/current_reaffirm_ts" 2>/dev/null | tr -d ' \r\n')"
		case "$last" in
			""|*[!0-9]*) last=0 ;;
		esac
		if [ -n "$ts" ] && [ $((ts - last)) -ge "$interval" ]; then
			if [ "$QSC_CW_OVER" = "1" ]; then
				if [ "$QSC_CW_FORCE" != "1" ]; then
					QSC_CW_FORCE=1
					QSC_CW_FORCE_REASON="periodic"
				fi
			else
				# 已压住：不写，只刷新周期，避免空转到期
				echo "$ts" >"$DATADIR/current_reaffirm_ts" 2>/dev/null
			fi
		fi
	fi
}

# 单节点写入：目标为节点原生单位；写后读回并重试
# $3=1 时强制写入（忽略「读回已相等」快路径）；强制时只试 1 次以省 I/O
qsc_current_write_one() {
	local node="$1" want="$2" force="${3:-0}"
	local cur i after max_try=3
	[ -f "$node" ] || return 1
	# 先读再决定是否 chmod/echo，相等且非强制则零写入
	cur="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
	case "$cur" in
		""|*[!0-9-]*) cur="" ;;
	esac
	if [ "$force" != "1" ] && [ -n "$cur" ] && [ "$cur" = "$want" ]; then
		QSC_CW_RB="$cur"
		return 0
	fi
	chown 0:0 "$node" 2>/dev/null
	chmod 0644 "$node" 2>/dev/null
	[ "$force" = "1" ] && max_try=1
	i=0
	while [ "$i" -lt "$max_try" ]; do
		echo "$want" >"$node" 2>/dev/null || true
		QSC_CW_DID_WRITE=1
		qsc_current_usleep
		after="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
		case "$after" in
			""|*[!0-9-]*) after="" ;;
		esac
		if [ -n "$after" ] && [ "$after" = "$want" ]; then
			QSC_CW_RB="$after"
			return 0
		fi
		# 读回相对写入前已变化 → 内核有响应
		if [ -n "$after" ] && [ -n "$cur" ] && [ "$after" != "$cur" ]; then
			QSC_CW_RB="$after"
			return 0
		fi
		i=$((i + 1))
	done
	QSC_CW_RB="${after:-$cur}"
	# 强制重申：即使读回未变也视为已施加（避免因撒谎读回判失败）
	if [ "$force" = "1" ]; then
		return 0
	fi
	return 1
}

# 写入电流目标（内部单位 µA）
# 副作用：QSC_CW_HIT / QSC_CW_OK / QSC_CW_FROM / QSC_CW_TO / QSC_CW_RB / QSC_CW_NODE / QSC_CW_SCALE
# 可选环境：QSC_CW_FORCE=1 强制重申（忽略读回相等快路径；优先只写工作节点）
qsc_current_write_target() {
	local target_ua="$1"
	local entry path scale want_native cur hit=0 ok=0
	local working="$DATADIR/ch_curr_working" session_fail="$DATADIR/.ch_curr_session_fail"
	local step_on="" step_native next
	local force="${QSC_CW_FORCE:-0}" entries="" use_working=0

	QSC_CW_HIT=0
	QSC_CW_OK=0
	QSC_CW_FROM=""
	QSC_CW_TO=""
	QSC_CW_RB=""
	QSC_CW_NODE=""
	QSC_CW_SCALE=""
	QSC_CW_REACHED=0
	QSC_CW_STEPPING=0
	QSC_CW_DID_WRITE=0

	case "$target_ua" in
		""|*[!0-9]*) return 1 ;;
	esac
	if [ "$target_ua" != "0" ] && [ "$target_ua" -lt 100000 ]; then
		target_ua=100000
	fi
	if [ "$target_ua" -gt 10000000 ]; then
		target_ua=10000000
	fi

	# 可选台阶（默认关）：current_step_ua，如 500000
	step_on="$(qsc_current_conf_get current_step_ua 2>/dev/null)"
	case "$step_on" in
		""|0|*[!0-9]*) step_on=0 ;;
	esac

	# 有工作节点表时只巡检这些（强制/常规都如此），少读少写
	if [ -s "$working" ]; then
		while IFS= read -r entry || [ -n "$entry" ]; do
			entry="$(printf '%s' "$entry" | tr -d ' \r\n')"
			[ -n "$entry" ] || continue
			entries="$entries $entry"
			use_working=1
		done <"$working"
	fi
	[ -z "$(echo "$entries" | tr -d ' ')" ] && entries="$QSC_CURR_ENTRIES"

	: >"$DATADIR/.ch_curr_ok_tmp" 2>/dev/null

	for entry in $entries; do
		path="${entry%%::*}"
		scale="${entry##*::}"
		[ -n "$path" ] && [ -f "$path" ] || continue
		qsc_current_node_denied "$path" && continue

		if [ "$force" != "1" ] && [ -f "$session_fail" ] && grep -q "^${path}$" "$session_fail" 2>/dev/null; then
			continue
		fi

		hit=1
		# 主路径 CCCM：一律按微安写（与 mA×1000 一致）
		case "$path" in
			*/constant_charge_current_max)
				scale=1
				want_native="$target_ua"
				;;
			*)
				case "$scale" in
					1000) want_native=$((target_ua / 1000)) ;;
					*)
						scale=1
						want_native="$target_ua"
						;;
				esac
				;;
		esac

		cur="$(cat "$path" 2>/dev/null | tr -d ' \r\n')"
		case "$cur" in
			""|*[!0-9]*) cur="" ;;
		esac

		# 降流可选台阶（current_step_ua）；抬流按约 300mA 分档逼近（强制重申时跳过台阶，直接目标）
		if [ "$force" != "1" ] && [ -n "$cur" ] && [ "$want_native" -gt "$cur" ] 2>/dev/null; then
			if [ "$scale" = "1000" ]; then
				step_native=300
			else
				step_native=300000
			fi
			next=$((cur + step_native))
			if [ "$next" -lt "$want_native" ]; then
				want_native="$next"
				QSC_CW_STEPPING=1
			fi
		elif [ "$force" != "1" ] && [ "$step_on" != "0" ] && [ "$want_native" != "0" ] && [ -n "$cur" ]; then
			step_native=$((step_on / scale))
			[ "$step_native" -lt 1 ] && step_native=1
			next=$((cur - step_native))
			if [ "$next" -gt "$want_native" ]; then
				want_native="$next"
				QSC_CW_STEPPING=1
			fi
		fi

		[ -z "$QSC_CW_FROM" ] && QSC_CW_FROM="$cur"
		QSC_CW_TO="$want_native"
		QSC_CW_NODE="$path"
		QSC_CW_SCALE="$scale"

		if qsc_current_write_one "$path" "$want_native" "$force"; then
			ok=1
			QSC_CW_REACHED=1
			echo "$path::$scale" >>"$DATADIR/.ch_curr_ok_tmp"
			if [ -f "$session_fail" ]; then
				grep -v "^${path}$" "$session_fail" >"$DATADIR/.ch_curr_sf2" 2>/dev/null
				mv "$DATADIR/.ch_curr_sf2" "$session_fail" 2>/dev/null
			fi
		else
			echo "$path" >>"$session_fail" 2>/dev/null
		fi
	done

	# 若全部因 session_fail 被跳过，清空失败表再试一轮（强制且已用工作表则回退全表）
	if [ "$hit" = "0" ] && [ -n "$(echo "$QSC_CURR_ENTRIES" | tr -d ' ')" ]; then
		rm -f "$session_fail"
		if [ "$use_working" = "1" ]; then
			entries="$QSC_CURR_ENTRIES"
		fi
		for entry in $entries; do
			path="${entry%%::*}"
			scale="${entry##*::}"
			[ -f "$path" ] || continue
			qsc_current_node_denied "$path" && continue
			hit=1
			case "$path" in
				*/constant_charge_current_max)
					scale=1
					want_native="$target_ua"
					;;
				*)
					case "$scale" in
						1000) want_native=$((target_ua / 1000)) ;;
						*) want_native="$target_ua"; scale=1 ;;
					esac
					;;
			esac
			cur="$(cat "$path" 2>/dev/null | tr -d ' \r\n')"
			[ -z "$QSC_CW_FROM" ] && QSC_CW_FROM="$cur"
			QSC_CW_TO="$want_native"
			QSC_CW_NODE="$path"
			QSC_CW_SCALE="$scale"
			if qsc_current_write_one "$path" "$want_native" "$force"; then
				ok=1
				QSC_CW_REACHED=1
				echo "$path::$scale" >>"$DATADIR/.ch_curr_ok_tmp"
			fi
		done
	fi

	if [ -s "$DATADIR/.ch_curr_ok_tmp" ]; then
		sort -u "$DATADIR/.ch_curr_ok_tmp" -o "$working"
	fi
	rm -f "$DATADIR/.ch_curr_ok_tmp"

	# 实际写入后刷新重申时钟；漂移强制成功则清 streak
	if [ "${QSC_CW_DID_WRITE:-0}" = "1" ]; then
		date +%s >"$DATADIR/current_reaffirm_ts" 2>/dev/null
		if [ "${QSC_CW_FORCE_REASON:-}" = "drift" ]; then
			echo 0 >"$DATADIR/current_drift_streak" 2>/dev/null
		fi
	elif [ "$force" = "1" ] && [ "$ok" = "1" ]; then
		# 强制但未真正 echo（极端）仍推进时钟，避免死循环狂刷
		date +%s >"$DATADIR/current_reaffirm_ts" 2>/dev/null
	fi

	QSC_CW_HIT="$hit"
	QSC_CW_OK="$ok"
	[ "$ok" = "1" ]
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
	local enable battery_stop slow_charge temp_cur bypass_en
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

	# 限流前先写 restricted，并准备节点权限
	qsc_current_prepare_once
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
	# 旧配置无字段：视为开启，保持原触发逻辑
	bypass_en="$(qsc_current_conf_get bypass_enable)"
	if [ -z "$bypass_en" ]; then
		bypass_en=1
	else
		bypass_en="$(qsc_clamp_int "$bypass_en" 0 1 0)"
	fi

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

	# 旁路总开关关闭：本轮不触发旁路与回补
	if [ "$bypass_en" != "1" ]; then
		battery_stop=110
		bypass_temp=110
	fi
	battery_stop_1=$((battery_stop - 1))

	# 电流温控档位：2=二限，1=一限
	if [ "$temp_cur" = "1" ] && [ -n "$temperature" ]; then
		if [ "$temperature" -ge "$limit2" ]; then
			cpu_log=2
		elif [ "$temperature" -ge "$limit1" ]; then
			cpu_log=1
		fi
	fi

	# 旁路：电量 / 温度 / 时段（总开关关闭时跳过）
	if [ "$bypass_en" = "1" ]; then
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

	# 每轮：先看实测电流。已压住且模式未变则整轮不碰 sysfs。
	reason="${mode_tag}:${target}"
	prev_tag="$(cat "$DATADIR/current_mode_tag" 2>/dev/null)"
	reached="$(cat "$DATADIR/current_reached" 2>/dev/null | tr -d ' \r\n')"

	qsc_current_decide_force "$target"

	if [ "${QSC_CW_FORCE:-0}" != "1" ] \
		&& [ "${QSC_CW_OVER:-0}" != "1" ] \
		&& [ "$prev_tag" = "$reason" ] \
		&& [ "$reached" = "1" ]; then
		# 偏小/正常：零节点 I/O
		return 0
	fi

	if ! qsc_current_write_target "$target"; then
		if [ "$prev_tag" != "fail:$reason" ]; then
			echo "$(date +%F_%T) 电量$battery_level 电流写入未生效：${log_name} 目标$(qsc_fmt_ma "$target") 节点=${QSC_CW_NODE:-?} scale=${QSC_CW_SCALE:-?} 读回=${QSC_CW_RB:-?}" >>"$LOG_FILE"
			echo "fail:$reason" >"$DATADIR/current_mode_tag"
		fi
		return 0
	fi

	now_c="${QSC_CW_NOW_UA:-$(qsc_current_now_ua)}"
	# 同模式只在切换、步进或漂移重申时记一行，避免刷屏
	if [ "$prev_tag" != "$reason" ] || [ "${QSC_CW_STEPPING:-0}" = "1" ] \
		|| { [ "${QSC_CW_FORCE_REASON:-}" = "drift" ] && [ "${QSC_CW_DID_WRITE:-0}" = "1" ]; }; then
		_extra=""
		[ "${QSC_CW_FORCE_REASON:-}" = "drift" ] && _extra=" 漂移重申"
		[ "${QSC_CW_FORCE_REASON:-}" = "periodic" ] && [ "${QSC_CW_DID_WRITE:-0}" = "1" ] && _extra=" 周期重申"
		echo "$(date +%F_%T) 电量$battery_level ${log_name}：限制电流$(qsc_fmt_ma "$target") 节点=$(qsc_node_short "${QSC_CW_NODE}") scale=${QSC_CW_SCALE} 读回=${QSC_CW_RB} 实时${now_c} 温度${temperature}${_extra}" >>"$LOG_FILE"
	fi
	echo "$reason" >"$DATADIR/current_mode_tag"
	if [ "${QSC_CW_STEPPING:-0}" = "1" ]; then
		echo 0 >"$DATADIR/current_reached"
	else
		echo 1 >"$DATADIR/current_reached"
	fi
	date +%s >"$DATADIR/current_write_ts" 2>/dev/null
}
