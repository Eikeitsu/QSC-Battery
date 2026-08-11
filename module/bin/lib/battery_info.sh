#!/system/bin/sh
# 电池健康 / 容量 / 循环（Action 与 WebUI 共用）
# 直接执行输出 key=value；被 source 时仅提供函数。

qsc_battery_sysfs_first() {
	_v=""
	for _f in "$@"; do
		[ -r "$_f" ] || continue
		_v=$(cat "$_f" 2>/dev/null | head -n1 | tr -d ' \r\n')
		[ -n "$_v" ] && { echo "$_v"; return 0; }
	done
	return 1
}

# µAh → mAh（常见 charge_full*）；已是 mAh 则原样返回
qsc_battery_uah_to_mah() {
	_u="$1"
	case "$_u" in
		""|*[!0-9]*) echo ""; return 1 ;;
	esac
	if [ "$_u" -ge 100000 ]; then
		echo $((_u / 1000))
	else
		echo "$_u"
	fi
}

# 填充：QSC_BATT_HEALTH / SOH / DESIGN_MAH / FULL_MAH / CYCLES（缺省为空）
qsc_battery_info_collect() {
	QSC_BATT_HEALTH=""
	QSC_BATT_SOH=""
	QSC_BATT_DESIGN_MAH=""
	QSC_BATT_FULL_MAH=""
	QSC_BATT_CYCLES=""

	QSC_BATT_HEALTH=$(qsc_battery_sysfs_first \
		/sys/class/power_supply/battery/health \
		/sys/class/power_supply/bms/health) || true

	QSC_BATT_SOH=$(qsc_battery_sysfs_first \
		/sys/class/power_supply/bms/soh \
		/sys/class/power_supply/battery/soh \
		/sys/class/power_supply/bms/battery_soh \
		/sys/class/qcom-battery/soh) || true

	_design_raw=$(qsc_battery_sysfs_first \
		/sys/class/power_supply/battery/charge_full_design \
		/sys/class/power_supply/bms/charge_full_design) || true
	_full_raw=$(qsc_battery_sysfs_first \
		/sys/class/power_supply/battery/charge_full \
		/sys/class/power_supply/bms/charge_full) || true

	QSC_BATT_DESIGN_MAH=$(qsc_battery_uah_to_mah "$_design_raw") || true
	QSC_BATT_FULL_MAH=$(qsc_battery_uah_to_mah "$_full_raw") || true

	QSC_BATT_CYCLES=$(qsc_battery_sysfs_first \
		/sys/class/power_supply/battery/cycle_count \
		/sys/class/power_supply/bms/cycle_count \
		/sys/class/power_supply/battery/battery_cycle \
		/sys/class/qcom-battery/cycle_count) || true

	# 无 soh 时用 真实/设计 估算
	if [ -z "$QSC_BATT_SOH" ] && [ -n "$QSC_BATT_FULL_MAH" ] && [ -n "$QSC_BATT_DESIGN_MAH" ] && [ "$QSC_BATT_DESIGN_MAH" -gt 0 ]; then
		QSC_BATT_SOH=$((QSC_BATT_FULL_MAH * 100 / QSC_BATT_DESIGN_MAH))
		[ "$QSC_BATT_SOH" -gt 100 ] && QSC_BATT_SOH=100
	fi
	case "$QSC_BATT_SOH" in
		""|*[!0-9]*) QSC_BATT_SOH="" ;;
		*)
			# 部分机型 soh 为 0–1000（0.1%）
			if [ "$QSC_BATT_SOH" -gt 100 ] && [ "$QSC_BATT_SOH" -le 1000 ]; then
				QSC_BATT_SOH=$((QSC_BATT_SOH / 10))
			fi
			;;
	esac
	case "$QSC_BATT_CYCLES" in
		""|*[!0-9]*) QSC_BATT_CYCLES="" ;;
	esac
}

# WebUI / 脚本解析用
qsc_battery_info_kv() {
	qsc_battery_info_collect
	echo "health=${QSC_BATT_HEALTH}"
	echo "soh=${QSC_BATT_SOH}"
	echo "design_mah=${QSC_BATT_DESIGN_MAH}"
	echo "full_mah=${QSC_BATT_FULL_MAH}"
	echo "cycle_count=${QSC_BATT_CYCLES}"
}

# Action 人类可读输出（无数据则不打印）
qsc_battery_info_echo() {
	qsc_battery_info_collect
	_health_line=""
	[ -n "$QSC_BATT_HEALTH" ] && _health_line="$QSC_BATT_HEALTH"
	[ -n "$QSC_BATT_SOH" ] && _health_line="${_health_line}${_health_line:+ · }SOH ${QSC_BATT_SOH}%"
	[ -n "$_health_line" ] && echo "健康: $_health_line"
	[ -n "$QSC_BATT_DESIGN_MAH" ] && echo "设计容量: ${QSC_BATT_DESIGN_MAH} mAh"
	[ -n "$QSC_BATT_FULL_MAH" ] && echo "真实容量: ${QSC_BATT_FULL_MAH} mAh"
	[ -n "$QSC_BATT_CYCLES" ] && echo "循环次数: $QSC_BATT_CYCLES"
}

case "${0##*/}" in
	battery_info.sh) qsc_battery_info_kv ;;
esac
