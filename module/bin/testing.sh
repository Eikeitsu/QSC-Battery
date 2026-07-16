#!/system/bin/sh
# 如发现模块 BUG，执行此脚本并把结果截图给作者
. "${0%/*}/common.sh"

dumpsys battery reset
module_version="$(cat "$MODDIR/module.prop" | egrep 'version=' | sed -n 's/.*version=//g;$p')"
Host_version="$(cat "$BINDIR/qsc_switch.sh" | egrep '^#version=' | sed -n 's/.*version=//g;$p')"
state="$(cat "$MODDIR/module.prop" | egrep '^description=' | sed -n 's/.*=\[//g;s/\].*//g;p')"
config_conf="$(cat "$CONF" | egrep -v '^#')"
dumpsys_battery="$(dumpsys battery)"
battery_level="$(echo "$dumpsys_battery" | egrep 'level: ' | sed -n 's/.*level: //g;$p')"
now_current="$(cat '/sys/class/power_supply/battery/current_now')"
power_stop_time="$(echo "$config_conf" | egrep '^power_stop_time=' | sed -n 's/power_stop_time=//g;$p')"
charge_full="$(echo "$config_conf" | egrep '^charge_full=' | sed -n 's/charge_full=//g;$p')"
power_reset="$(echo "$config_conf" | egrep '^power_reset=' | sed -n 's/power_reset=//g;$p')"
temperature="$(echo "$dumpsys_battery" | egrep 'temperature: ' | sed -n 's/.*temperature: //g;s/.$//g;$p')"
power_stop="$(echo "$config_conf" | egrep '^power_stop=' | sed -n 's/power_stop=//g;$p')"
power_start="$(echo "$config_conf" | egrep '^power_start=' | sed -n 's/power_start=//g;$p')"
temperature_switch="$(echo "$config_conf" | egrep '^temperature_switch=' | sed -n 's/temperature_switch=//g;$p')"
temperature_switch_stop="$(echo "$config_conf" | egrep '^temperature_switch_stop=' | sed -n 's/temperature_switch_stop=//g;$p')"
temperature_switch_start="$(echo "$config_conf" | egrep '^temperature_switch_start=' | sed -n 's/temperature_switch_start=//g;$p')"
battery_powered="$(echo "$dumpsys_battery" | egrep 'powered: true')"
battery_status="$(echo "$dumpsys_battery" | egrep 'status: ' | sed -n 's/.*status: //g;$p')"
dumpsys_charging="$(dumpsys deviceidle get charging)"
if [ -n "$battery_powered" ]; then
	dumpsys_powered=1
else
	dumpsys_powered=0
fi
echo ---------- 适配 ------------
dumpsys battery
echo "$state"
if [ -f "$DATADIR/power_on" ]; then power_on="1"; else power_on="0"; fi
if [ -f "$DATADIR/power_off" ]; then power_off="1"; else power_off="0"; fi
if [ -f "$DATADIR/power_switch" ]; then power_switch="1"; else power_switch="0"; fi
echo "充电状态$dumpsys_charging,$dumpsys_powered,$battery_status,电量$battery_level,电流$now_current,power_on$power_on,power_off$power_off,power_switch$power_switch,停止充电电量$power_stop,恢复充电电量$power_start,开关温控$temperature_switch,停止温度$temperature_switch_stop,恢复温度$temperature_switch_start,温度$temperature,延时$power_stop_time,充满再停$charge_full,自动拔插$power_reset"
echo ---------- 搜索开关 ------------
switch_list="$(cat "$LIST_SWITCH")"
switch_list="$switch_list /sys/class/power_supply/battery/batt_slate_mode,start=0,stop=1 /sys/class/power_supply/battery/store_mode,start=0,stop=1 /sys/class/power_supply/battery/input_suspend,start=0,stop=1 /sys/class/power_supply/battery/charging_enabled,start=1,stop=0 /sys/class/power_supply/battery/charge_disable,start=0,stop=1 /sys/class/power_supply/battery/disable_charging,start=0,stop=1 /sys/class/power_supply/battery/stop_charging,start=0,stop=1 /sys/class/power_supply/battery/charge_enabled,start=1,stop=0 /sys/class/power_supply/charger/charge_disable,start=0,stop=1 /sys/class/power_supply/bms/charge_disable,start=0,stop=1 /sys/class/power_supply/bms/charging_enabled,start=1,stop=0 /sys/class/power_supply/bms/charge_enabled,start=1,stop=0 /sys/class/power_supply/mi_chg/charge_disable,start=0,stop=1 /sys/class/power_supply/mi_chg/charging_enabled,start=1,stop=0 /sys/class/qcom-battery/charging_enabled,start=1,stop=0 /sys/class/qcom-battery/charge_disable,start=0,stop=1 /sys/class/qcom-battery/input_suspend,start=0,stop=1 /sys/class/qcom-battery/battery_charging_enabled,start=1,stop=0 /sys/class/power_supply/idt/pin_enabled,start=1,stop=0 /sys/kernel/debug/google_charger/chg_suspend,start=0,stop=1 /sys/kernel/debug/google_charger/chg_mode,start=1,stop=0 /proc/driver/charger_limit_enable,start=0,stop=1 /proc/driver/charger_limit,start=100,stop=1 /proc/mtk_battery_cmd/current_cmd,start=0_0,stop=0_1 /proc/mtk_battery_cmd/en_power_path,start=1,stop=0 /sys/devices/platform/soc/soc:mca_business_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/soc:mca_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/soc@0:mca_business_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/soc@0:mca_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/mca_business_charger/handle_state,start=0,stop=1 /sys/devices/platform/soc/mca_charger/handle_state,start=0,stop=1"
for i in $switch_list ; do
	power_switch_route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
	if [ -f "$power_switch_route" ]; then
		power_switch_data="$(cat "$power_switch_route")"
		power_list="$power_switch_route,$power_switch_data,$power_list"
	fi
done
echo "$power_list"
echo ---------- 机型 ------------
echo "module.$(echo $module_version | sed -n 's/ //g;$p'),version.$(echo $Host_version | sed -n 's/ //g;$p'),release.$(getprop ro.build.version.release | sed -n 's/ //g;$p'),sdk.$(getprop ro.build.version.sdk | sed -n 's/ //g;$p'),brand.$(getprop ro.product.brand | sed -n 's/ //g;$p'),model.$(getprop ro.product.model | sed -n 's/ //g;$p'),cpu.$(cat '/proc/cpuinfo' | egrep 'Hardware' | sed -n 's/.*://g;s/ //g;$p')"
# ##
