#!/system/bin/sh
. "${0%/*}/common.sh"

find /sys/*/* -type f -iname "*input_suspend" -o -type f -iname "*disable*_charge*" -o -type f -iname "*charge*_disable*" -o -type f -iname "*disable*_charging*" -o -type f -iname "*stop_charge*" -o -type f -iname "*stop_charging*" -o -type f -iname "*stop_handle_charge" -o -type f -iname "*batt_slate_mode" -o -type f -iname "*store_mode" -o -type f -iname "*night_charging" -o -type f -iname "*force_disable_charging" 2>/dev/null | egrep -i -v 'limit|max|float|step|reverse|/battery_|bq2597x|/cpu/|firmware' | sed -n 's/$/,start=0,stop=1/g;p' > "$LIST_SWITCH"

find /sys/*/* -type f -iname "*charging_enable*" -o -type f -iname "*enable*_charge*" -o -type f -iname "*charge*_enable*" -o -type f -iname "*enable*_charging*" -o -type f -iname "*charge*_control*" -o -type f -iname "*charging*_state*" 2>/dev/null | egrep -i -v 'limit|prohibit|prevent|disable|stop|restrict|reverse|max|float|step|/battery_|bq2597x|/cpu/|firmware|/qcom-battery/' | sed -n 's/$/,start=1,stop=0/g;p' >> "$LIST_SWITCH"

find /sys/*/* -type f -iname "*charging_enable*" -o -type f -iname "*enable*_charge*" -o -type f -iname "*charge*_enable*" -o -type f -iname "*enable*_charging*" -o -type f -iname "*charge*_control*" 2>/dev/null | egrep -i 'prohibit|prevent|disable|stop|restrict' | egrep -i -v 'limit|max|float|step|reverse|/battery_|bq2597x|/cpu/|firmware|/qcom-battery/' | sed -n 's/$/,start=0,stop=1/g;p' >> "$LIST_SWITCH"

find /sys/class/power_supply/*/ -maxdepth 1 -type f \( -iname "*charging_enabled" -o -iname "*charge_enabled" -o -iname "*charge_disable" -o -iname "*disable_charging" -o -iname "*charging_disable" -o -iname "*stop_charging" -o -iname "*charge_control_limit" \) 2>/dev/null | sed -n 's/$/,start=1,stop=0/g;p' >> "$LIST_SWITCH"

find /sys/class/qcom-battery/ -maxdepth 1 -type f \( -iname "*charging_enabled" -o -iname "*charge_enabled" -o -iname "*charge_disable" -o -iname "*disable_charging" -o -iname "*input_suspend" -o -iname "*battery_charging_enabled" \) 2>/dev/null | sed -n 's/$/,start=1,stop=0/g;p' >> "$LIST_SWITCH"

find /sys/devices/platform/soc/ -maxdepth 5 -type f -name "handle_state" -path "*mca*" 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >> "$LIST_SWITCH"
find /sys/devices/platform/soc/ -maxdepth 5 -type f -name "handle_state" -path "*charg*" 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >> "$LIST_SWITCH"

find /sys/devices/platform/ -maxdepth 6 -type f -name "handle_state" 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >> "$LIST_SWITCH"

find /sys/devices/platform/soc/ -maxdepth 5 -type f \( -iname "force_charging" -o -iname "enable_charging" -o -iname "charge_control" \) -path "*mca*" 2>/dev/null | sed -n 's/$/,start=1,stop=0/g;p' >> "$LIST_SWITCH"

find /sys/class/power_supply/ -maxdepth 2 -type f \( -iname "constant_charge_current_max" -o -iname "current_max" -o -iname "input_current_max" -o -iname "charge_current" -o -iname "fast_charge_current_max" \) 2>/dev/null | sed -n 's/$/,start=3000000,stop=0/g;p' >> "$LIST_SWITCH"

find /sys/class/power_supply/battery/ -maxdepth 1 -type f -iname "charge_type" 2>/dev/null | sed -n 's/$/,start=Fast,stop=None/g;p' >> "$LIST_SWITCH"

find /sys/class/power_supply/battery/ -maxdepth 1 -type f \( -iname "charge_control_end_threshold" -o -iname "charge_control_start_threshold" \) 2>/dev/null | sed -n 's/$/,start=100,stop=0/g;p' >> "$LIST_SWITCH"

find /sys/class/power_supply/ -maxdepth 2 -type f -iname "*charge_control_enabled" 2>/dev/null | sed -n 's/$/,start=1,stop=0/g;p' >> "$LIST_SWITCH"

find /sys/class/power_supply/ -maxdepth 2 -type f -iname "mi_charge_enable" 2>/dev/null | sed -n 's/$/,start=1,stop=0/g;p' >> "$LIST_SWITCH"

find /sys/class/power_supply/usb/ /sys/class/power_supply/qc_usb/ /sys/class/power_supply/dc/ /sys/class/power_supply/wireless/ /sys/class/power_supply/pc_port/ -maxdepth 1 -type f -iname "input_suspend" 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >> "$LIST_SWITCH"

find /sys/devices/platform/ -maxdepth 6 -type f -name "handle_state" \( -path "*mca*" -o -path "*charg*" \) 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >> "$LIST_SWITCH"

[ -f "$LIST_SWITCH" ] && sort -u "$LIST_SWITCH" -o "$LIST_SWITCH"

cat >> "$LIST_SWITCH" << 'EOF'
/sys/class/power_supply/battery/charging_enabled,start=1,stop=0
/sys/class/power_supply/battery/batt_slate_mode,start=0,stop=1
/sys/class/power_supply/battery/store_mode,start=0,stop=1
/sys/class/power_supply/battery/input_suspend,start=0,stop=1
/sys/class/power_supply/battery/charge_disable,start=0,stop=1
/sys/class/power_supply/battery/disable_charging,start=0,stop=1
/sys/class/power_supply/battery/stop_charging,start=0,stop=1
/sys/class/power_supply/battery/charge_enabled,start=1,stop=0
/sys/class/power_supply/charger/charge_disable,start=0,stop=1
/sys/class/power_supply/bms/charge_disable,start=0,stop=1
/sys/class/power_supply/bms/charging_enabled,start=1,stop=0
/sys/class/power_supply/bms/charge_enabled,start=1,stop=0
/sys/class/power_supply/mi_chg/charge_disable,start=0,stop=1
/sys/class/power_supply/mi_chg/charging_enabled,start=1,stop=0
/sys/class/power_supply/battery/constant_charge_current_max,start=3000000,stop=0
/sys/class/power_supply/battery/current_max,start=3000000,stop=0
/sys/class/power_supply/battery/input_current_max,start=3000000,stop=0
/sys/class/power_supply/battery/charge_current,start=3000000,stop=0
/sys/class/power_supply/battery/charge_type,start=Fast,stop=None
/sys/class/power_supply/battery/charge_control_end_threshold,start=100,stop=0
/sys/class/power_supply/battery/batt_charging_enabled,start=1,stop=0
/sys/class/power_supply/battery/force_disable_charging,start=0,stop=1
/sys/class/power_supply/battery/charge_control_enabled,start=1,stop=0
/sys/class/power_supply/battery/mi_charge_enable,start=1,stop=0
/sys/class/power_supply/usb/input_suspend,start=0,stop=1
/sys/class/power_supply/qc_usb/input_suspend,start=0,stop=1
/sys/class/power_supply/dc/input_suspend,start=0,stop=1
/sys/class/power_supply/wireless/input_suspend,start=0,stop=1
/sys/class/power_supply/pc_port/input_suspend,start=0,stop=1
/sys/kernel/debug/google_charger/chg_suspend,start=0,stop=1
/sys/kernel/debug/google_charger/chg_mode,start=1,stop=0
/proc/driver/charger_limit_enable,start=0,stop=1
/proc/driver/charger_limit,start=100,stop=1
/proc/mtk_battery_cmd/current_cmd,start=0_0,stop=0_1
/proc/mtk_battery_cmd/en_power_path,start=1,stop=0
EOF
# MCA 路径由 detect_device / device.profile 按本机动态写入，不再统一硬编码

echo "[QSC] list_switch.sh 执行完毕，已生成节点列表: $LIST_SWITCH" >&2
# ##
