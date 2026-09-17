#!/system/bin/sh
# QSC-Battery 统一 CLI
# 用法：
#   /data/adb/qsc/bin/qsc <命令> …
#   sh /data/adb/modules/QSC_Battery/bin/qsc.sh <命令> …

MODDIR="${MODDIR:-/data/adb/modules/QSC_Battery}"
BINDIR="$MODDIR/bin"

if [ -f "$BINDIR/common.sh" ]; then
	# shellcheck disable=SC1090
	. "$BINDIR/common.sh"
else
	echo "错误：找不到 common.sh（模块是否已安装？）" >&2
	exit 1
fi

# 允许 CLI 改写的单行配置键（与 apps/webui/APP 常用项对齐）
QSC_CLI_CONF_KEYS="power_stop power_start power_stop_time charge_full charge_full_mode charge_full_wait_sec power_reset unplug_restore compatibility_mode shut_down loop_interval_sec loop_interval_maintain_sec switch_verify_sec switch_batch_blind wireless_policy app_stop app_stop_list history_enable history_interval_sec temperature_switch temperature_switch_stop temperature_switch_start notify_power_status notify_charge_event native_daemon native_impl"

qsc_cli_usage() {
	cat <<EOF
QSC-Battery CLI

用法: /data/adb/qsc/bin/qsc <命令> [参数]
      （等价于 sh $BINDIR/qsc.sh <命令>）

命令:
  status [--raw]          电池/模块状态（默认人类可读；--raw 为 APP 分段格式）
  on                      开启充电控制（删除 data/module_off）
  off                     关闭充电控制（写入 data/module_off，不卸载模块）
  toggle                  切换 on/off
  config list             列出可读写配置键及当前值
  config get <键>         读取配置
  config set <键> <值>    写入配置（仅白名单单行键）
  log [行数]              运行日志尾部（默认 40）
  events [行数]           充电事件尾部（默认 40）
  diagnose                运行诊断 → /sdcard/qsc_diagnose.txt
  test-switch             开关可逆测试（需插电）
  detect                  重新探测设备档案
  daemon <子命令...>      转交 qscd_fetch.sh（status|check|install|use|remove）
  version                 模块版本
  help                    显示本帮助

入口: /data/adb/qsc/bin/qsc（不挂 system）

示例:
  /data/adb/qsc/bin/qsc status
  /data/adb/qsc/bin/qsc config set power_stop 80
  /data/adb/qsc/bin/qsc off
EOF
}

qsc_cli_version() {
	local ver code
	ver="$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-)"
	code="$(grep '^versionCode=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-)"
	echo "QSC-Battery ${ver:-?} (versionCode ${code:-?})"
	echo "MODDIR=$MODDIR"
}

qsc_cli_is_on() {
	[ ! -f "$MODULE_OFF_FLAG" ] && [ ! -f "$MODDIR/disable" ]
}

qsc_cli_snap_kv() {
	# $1=key from snapshot print lines
	printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -n1 | tr -d '\r'
}

qsc_cli_status_human() {
	local snap level temp st plugged off stopped ver curr volt
	if command -v qsc_battery_snapshot_print >/dev/null 2>&1; then
		snap="$(qsc_battery_snapshot_print 2>/dev/null)"
	else
		snap="$(
			echo "level=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
			echo "temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)"
			echo "status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
			echo "powered=$(cat /sys/class/power_supply/battery/online 2>/dev/null)"
		)"
	fi
	level="$(qsc_cli_snap_kv level "$snap")"
	temp="$(qsc_cli_snap_kv temp "$snap")"
	st="$(qsc_cli_snap_kv status "$snap")"
	plugged="$(qsc_cli_snap_kv powered "$snap")"
	[ -z "$plugged" ] && plugged="$(qsc_cli_snap_kv plugged "$snap")"
	if [ -f "$MODULE_OFF_FLAG" ] || [ -f "$MODDIR/disable" ]; then off=1; else off=0; fi
	if [ -f "$DATADIR/power_switch" ]; then stopped=1; else stopped=0; fi
	ver="$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-)"
	curr="$(cat /sys/class/power_supply/battery/current_now 2>/dev/null | tr -d ' \r\n')"
	volt="$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null | tr -d ' \r\n')"

	echo "模块: ${ver:-?}  控制: $([ "$off" = "1" ] && echo 关 || echo 开)  停充标记: $([ "$stopped" = "1" ] && echo 是 || echo 否)"
	echo "电量: ${level:-?}%"
	echo "温度: ${temp:-?}"
	echo "状态: ${st:-?}  插电: ${plugged:-?}"
	echo "电流: ${curr:-?} uA  电压: ${volt:-?} uV"
	if [ -f "$CONF" ]; then
		echo "停充/恢复: $(grep '^power_stop=' "$CONF" 2>/dev/null | cut -d= -f2- | tr -d '\r')% → $(grep '^power_start=' "$CONF" 2>/dev/null | cut -d= -f2- | tr -d '\r')%"
	fi
}

qsc_cli_conf_is_allowed() {
	local key="$1" k
	for k in $QSC_CLI_CONF_KEYS; do
		[ "$k" = "$key" ] && return 0
	done
	return 1
}

qsc_cli_conf_get() {
	local key="$1" line
	[ -n "$key" ] || {
		echo "用法: config get <键>" >&2
		return 2
	}
	[ -f "$CONF" ] || {
		echo "错误：无配置文件 $CONF" >&2
		return 1
	}
	line="$(grep "^${key}=" "$CONF" 2>/dev/null | head -n1)"
	if [ -z "$line" ]; then
		echo "(未设置)"
		return 1
	fi
	echo "${line#*=}" | tr -d '\r'
}

qsc_cli_conf_set() {
	local key="$1" val="$2" tmp
	[ -n "$key" ] || {
		echo "用法: config set <键> <值>" >&2
		return 2
	}
	# 允许空字符串值以外：至少传入了第二个参数位置
	[ "$#" -ge 2 ] || {
		echo "用法: config set <键> <值>" >&2
		return 2
	}
	case "$val" in
		*=*)
			echo "错误：值不能含 '='" >&2
			return 2
			;;
	esac
	qsc_cli_conf_is_allowed "$key" || {
		echo "错误：不允许写入键 '$key'（见 config list）" >&2
		return 2
	}
	[ -f "$CONF" ] || {
		echo "错误：无配置文件 $CONF" >&2
		return 1
	}
	tmp="$DATADIR/.qsc_cli_conf.$$"
	mkdir -p "$DATADIR"
	awk -v k="$key" -v v="$val" '
		BEGIN { done=0 }
		{
			if (!done && $0 ~ ("^" k "=")) {
				print k "=" v
				done=1
			} else print
		}
		END { if (!done) print k "=" v }
	' "$CONF" >"$tmp" || {
		rm -f "$tmp"
		return 1
	}
	mv -f "$tmp" "$CONF" || {
		rm -f "$tmp"
		echo "错误：写入失败" >&2
		return 1
	}
	echo "已设置 $key=$val"
}

qsc_cli_conf_list() {
	local k cur
	[ -f "$CONF" ] || {
		echo "错误：无配置文件 $CONF" >&2
		return 1
	}
	for k in $QSC_CLI_CONF_KEYS; do
		cur="$(grep "^${k}=" "$CONF" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r')"
		[ -n "$cur" ] || cur="(未设置)"
		printf '%s=%s\n' "$k" "$cur"
	done
}

qsc_cli_tail() {
	local file="$1" n="${2:-40}"
	[ -f "$file" ] || {
		echo "(无文件: $file)" >&2
		return 1
	}
	case "$n" in
		""|*[!0-9]*) n=40 ;;
	esac
	tail -n "$n" "$file" 2>/dev/null || busybox tail -n "$n" "$file" 2>/dev/null
}

cmd="${1:-help}"
[ "$#" -gt 0 ] && shift

case "$cmd" in
	help|-h|--help) qsc_cli_usage ;;
	version|-v|--version) qsc_cli_version ;;
	status)
		case "${1:-}" in
			--raw) sh "$BINDIR/qsc_status.sh" ;;
			*) qsc_cli_status_human ;;
		esac
		;;
	on)
		rm -f "$MODULE_OFF_FLAG"
		echo "已开启充电控制"
		;;
	off)
		mkdir -p "$DATADIR"
		: >"$MODULE_OFF_FLAG"
		echo "已关闭充电控制（软开关；模块仍安装）"
		;;
	toggle)
		if qsc_cli_is_on; then
			mkdir -p "$DATADIR"
			: >"$MODULE_OFF_FLAG"
			echo "已关闭充电控制"
		else
			rm -f "$MODULE_OFF_FLAG"
			echo "已开启充电控制"
		fi
		;;
	config)
		sub="${1:-}"
		[ -n "$sub" ] && shift
		case "$sub" in
			list) qsc_cli_conf_list ;;
			get) qsc_cli_conf_get "$1" ;;
			set) qsc_cli_conf_set "$1" "$2" ;;
			*)
				echo "用法: config list|get <键>|set <键> <值>" >&2
				exit 2
				;;
		esac
		;;
	log) qsc_cli_tail "$LOG_FILE" "${1:-40}" ;;
	events) qsc_cli_tail "$DATADIR/charge_events.log" "${1:-40}" ;;
	diagnose)
		[ -f "$BINDIR/diagnose.sh" ] || {
			echo "缺少 diagnose.sh" >&2
			exit 1
		}
		sh "$BINDIR/diagnose.sh"
		;;
	test-switch|test_switch)
		[ -f "$BINDIR/test_switch.sh" ] || {
			echo "缺少 test_switch.sh" >&2
			exit 1
		}
		sh "$BINDIR/test_switch.sh"
		;;
	detect)
		[ -f "$BINDIR/detect_device.sh" ] || {
			echo "缺少 detect_device.sh" >&2
			exit 1
		}
		sh "$BINDIR/detect_device.sh"
		;;
	daemon)
		[ -f "$BINDIR/qscd_fetch.sh" ] || {
			echo "缺少 qscd_fetch.sh" >&2
			exit 1
		}
		sh "$BINDIR/qscd_fetch.sh" "$@"
		;;
	*)
		echo "未知命令: $cmd（试 help）" >&2
		exit 2
		;;
esac
