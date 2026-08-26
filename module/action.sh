#!/system/bin/sh
# Action：开头一轮音量二选一；超时默认刷新状态。
#   音量上 / 超时 → 短状态刷新
#   音量下       → 已插电：测停充开关；未插电：只读诊断
# Magisk / 官方 KSU / APatch 通常可跑完；SukiSU 约 10s 总时长，故测开关走快速模式。
# 改阈值 / 软开关 → WebUI。

MODDIR=${0%/*}

echo "======== 充电控制 · Action ========"

if [ ! -f "$MODDIR/bin/common.sh" ]; then
	echo "[错误] 缺少 bin/common.sh，请重新安装模块"
	exit 1
fi

. "$MODDIR/bin/common.sh"
mkdir -p "$DATADIR" 2>/dev/null

if [ ! -f "$LIBDIR/keys.sh" ]; then
	echo "[错误] 缺少 bin/lib/keys.sh"
	exit 1
fi
# shellcheck disable=SC1090
. "$LIBDIR/keys.sh"

echo "音量上：刷新状态"
echo "音量下：插电测开关（未插电 → 诊断报告）"
echo "5 秒内未按键 → 自动刷新状态"

qsc_volume_choice 5
_vol_rc=$?

qsc_action_is_plugged() {
	local s o
	s="$(cat /sys/class/power_supply/battery/status 2>/dev/null | tr -d ' \r\n')"
	case "$s" in
		Charging|Full) return 0 ;;
	esac
	for o in /sys/class/power_supply/usb/online \
		/sys/class/power_supply/qc_usb/online \
		/sys/class/power_supply/wireless/online; do
		[ -f "$o" ] && [ "$(cat "$o" 2>/dev/null | tr -d ' \r\n')" = "1" ] && return 0
	done
	return 1
}

qsc_action_refresh() {
	echo "-------- 状态 --------"

	chmod 0755 "$BINDIR"/*.sh 2>/dev/null
	[ -d "$BINDIR/lib" ] && chmod 0755 "$BINDIR/lib"/*.sh 2>/dev/null
	[ -f "$CONF" ] && chmod 0644 "$CONF" 2>/dev/null
	[ -f "$CURRENT_CONF" ] && chmod 0644 "$CURRENT_CONF" 2>/dev/null
	if [ -d "$MODDIR/webroot" ]; then
		chmod 0755 "$MODDIR/webroot" "$MODDIR/webroot"/js "$MODDIR/webroot"/css 2>/dev/null
		chmod 0644 "$MODDIR/webroot"/*.* "$MODDIR/webroot"/js/* "$MODDIR/webroot"/css/* 2>/dev/null
	fi

	_ver=$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-)
	[ -n "$_ver" ] && echo "版本: $_ver"

	if [ ! -f "$BINDIR/qsc_switch.sh" ]; then
		echo "模块: 核心脚本缺失"
	elif [ -f "$MODDIR/disable" ]; then
		echo "模块: 管理器已禁用"
	elif [ -f "$OFF_FLAG" ]; then
		echo "模块: 软关闭"
	else
		echo "模块: 开启"
	fi

	_cap=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null | tr -d ' \r\n')
	_temp_raw=$(cat /sys/class/power_supply/battery/temp 2>/dev/null | tr -d ' \r\n')
	_batt_st=$(cat /sys/class/power_supply/battery/status 2>/dev/null | tr -d ' \r\n')
	_usb=$(cat /sys/class/power_supply/usb/online 2>/dev/null | tr -d ' \r\n')
	_curr=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null | tr -d ' \r\n')

	_live=""
	_temp_c=""
	[ -n "$_cap" ] && _live="电量 ${_cap}%"
	if [ -n "$_temp_raw" ]; then
		case "$_temp_raw" in
			*[!0-9-]*) ;;
			*)
				_temp_c=$((_temp_raw / 10))
				_live="${_live}${_live:+ · }${_temp_c}°C"
				;;
		esac
	fi
	[ -n "$_batt_st" ] && _live="${_live}${_live:+ · }${_batt_st}"
	[ -n "$_live" ] && echo "电池: $_live"
	[ "$_usb" = "1" ] && echo "USB: 已连接"
	if [ -n "$_curr" ]; then
		case "$_curr" in
			*[!0-9-]*) ;;
			*) echo "电流: $((_curr / 1000)) mA" ;;
		esac
	fi

	qsc_battery_info_echo

	if [ -f "$DATADIR/power_switch" ]; then
		_why=""
		[ -f "$DATADIR/battery_switch" ] && _why="电量"
		if [ -f "$DATADIR/temp_switch" ]; then
			[ -n "$_why" ] && _why="${_why}+温度" || _why="温度"
		fi
		[ -n "$_why" ] && echo "停充态: 是（$_why）" || echo "停充态: 是"
	elif [ -f "$OFF_FLAG" ] || [ -f "$MODDIR/disable" ]; then
		echo "停充态: —"
	else
		echo "停充态: 否"
	fi
	[ -f "$DATADIR/no_node_logged" ] && echo "警告: 曾无可用停充节点"
	[ -f "$DATADIR/stop_fail_hint" ] && echo "提示: 停充可能未真正生效，请插电测开关"
	[ -f "$MODDIR/webroot/index.html" ] || echo "WebUI: 未安装"

	_conf_get() {
		sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -n1 | tr -d ' \r'
	}
	if [ -f "$CONF" ]; then
		_ps=$(_conf_get power_stop)
		_pt=$(_conf_get power_start)
		_ts=$(_conf_get temperature_switch)
		_tst=$(_conf_get temperature_switch_stop)
		_tsr=$(_conf_get temperature_switch_start)
		_cm=$(_conf_get Compatibility_mode)
		_wl=$(_conf_get stop_hold_wakelock)
		echo "停充/复充: ${_ps:-?}% / ${_pt:-?}%"
		if [ "$_ts" = "1" ]; then
			echo "温度停充: ${_tst:-?}°C → ${_tsr:-?}°C"
		fi
		[ "$_cm" = "1" ] && echo "兼容模式: 开"
		[ -n "$_wl" ] && echo "停充持锁: $_wl"
	else
		echo "配置文件缺失"
	fi

	if [ -f "$CURRENT_CONF" ]; then
		_cc=$(qsc_jsonc_get "$CURRENT_CONF" current_control 2>/dev/null)
		[ "$_cc" = "1" ] && echo "电流控制: 开" || echo "电流控制: 关"
	fi

	if [ -f "$DEVICE_PROFILE" ]; then
		_mca=$(qsc_profile_get mca 2>/dev/null)
		_pref=$(qsc_profile_get preferred_switch 2>/dev/null)
		[ -n "$_mca" ] && echo "MCA: $_mca"
		[ -n "$_pref" ] && echo "优选开关: .../${_pref##*/}" || echo "优选开关: 未实测"
	else
		echo "机型档案: 尚未生成"
	fi

	battery_level="$_cap"
	temperature="$_temp_c"
	[ -f "$OFF_FLAG" ] || [ -f "$MODDIR/disable" ] && off_qsc=1
	command -v qsc_refresh_module_description >/dev/null 2>&1 && \
		qsc_refresh_module_description >/dev/null 2>&1

	echo "-------- 说明 --------"
	echo "日志: $LOG_FILE"
	echo "诊断: sh $BINDIR/diagnose.sh"
	[ -f "$BINDIR/test_switch.sh" ] && echo "完整测开关: sh $BINDIR/test_switch.sh"
	[ -f "$BINDIR/detect_device.sh" ] && echo "重新探测: sh $BINDIR/detect_device.sh"
	echo "升级后闪充/无效：可删 data/list_switch 与 device.profile 后重启"
	echo "日常设置 / 软开关 → WebUI"
}

qsc_action_diagnose() {
	echo "-------- 功能诊断 --------"
	if [ ! -f "$BINDIR/diagnose.sh" ]; then
		echo "缺少 diagnose.sh"
		return 1
	fi
	chmod 0755 "$BINDIR/diagnose.sh" 2>/dev/null
	echo "正在生成报告 → /sdcard/qsc_diagnose.txt"
	sh "$BINDIR/diagnose.sh"
}

qsc_action_test_switch() {
	echo "-------- 停充开关实测 --------"
	if [ ! -f "$BINDIR/test_switch.sh" ]; then
		echo "缺少 test_switch.sh"
		return 1
	fi
	if ! qsc_action_is_plugged; then
		echo "未检测到充电器，改为生成诊断报告"
		qsc_action_diagnose
		return $?
	fi
	chmod 0755 "$BINDIR/test_switch.sh" 2>/dev/null
	# Action 快速模式后台跑，避免管理器超时杀进程
	echo "已插电：后台快速测开关（最多约 12 条）…"
	echo "状态: $DATADIR/switch_test_status · 日志: $DATADIR/switch_test.log"
	echo "完整测试: sh $BINDIR/test_switch.sh 或 WebUI「完整测开关」"
	QSC_TEST_MAX=12 sh "$BINDIR/test_switch_bg.sh"
	sleep 1
	[ -f "$DATADIR/switch_test_status" ] && echo "当前: $(cat "$DATADIR/switch_test_status" 2>/dev/null)"
	return 0
}

case "$_vol_rc" in
	1)
		echo "→ 测开关 / 诊断"
		qsc_action_test_switch
		;;
	0)
		echo "→ 刷新状态"
		qsc_action_refresh
		;;
	*)
		echo "→ 超时，自动刷新状态"
		qsc_action_refresh
		;;
esac

echo "======== 结束 ========"
