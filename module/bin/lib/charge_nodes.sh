#!/system/bin/sh
# charge: switch node lists

# 各机型常见停充节点；运行时仍以文件是否存在为准。值里空格用 _ 表示（写入前还原）。
# 真正供电开关优先；电流伪开关 / 输入口 suspend 放在 QSC_LAST_RESORT_SWITCHES。
QSC_FALLBACK_SWITCHES="\
/sys/class/power_supply/battery/charge_charger_state,start=1,stop=0 \
/sys/class/power_supply/battery/connect_disable,start=0,stop=1 \
/sys/class/power_supply/battery/batt_slate_mode,start=0,stop=1 \
/sys/class/power_supply/battery/store_mode,start=0,stop=1 \
/sys/class/power_supply/battery/input_suspend,start=0,stop=1 \
/sys/class/power_supply/battery/battery_input_suspend,start=0,stop=1 \
/sys/class/power_supply/battery/charging_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/battery_charging_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/batt_charging_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/charge_disable,start=0,stop=1 \
/sys/class/power_supply/battery/disable_charging,start=0,stop=1 \
/sys/class/power_supply/battery/stop_charging,start=0,stop=1 \
/sys/class/power_supply/battery/charge_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/op_disable_charge,start=0,stop=1 \
/sys/class/power_supply/battery/device/Charging_Enable,start=1,stop=0 \
/sys/class/power_supply/battery/ChargerEnable,start=1,stop=0 \
/sys/class/power_supply/battery/force_disable_charging,start=0,stop=1 \
/sys/class/power_supply/battery/charge_control_enabled,start=1,stop=0 \
/sys/class/power_supply/battery/mi_charge_enable,start=1,stop=0 \
/sys/class/power_supply/charger/charge_disable,start=0,stop=1 \
/sys/class/power_supply/bms/charge_disable,start=0,stop=1 \
/sys/class/power_supply/bms/charging_enabled,start=1,stop=0 \
/sys/class/power_supply/bms/charge_enabled,start=1,stop=0 \
/sys/class/power_supply/mi_chg/charge_disable,start=0,stop=1 \
/sys/class/power_supply/mi_chg/charging_enabled,start=1,stop=0 \
/sys/class/qcom-battery/charging_enabled,start=1,stop=0 \
/sys/class/qcom-battery/charge_disable,start=0,stop=1 \
/sys/class/qcom-battery/input_suspend,start=0,stop=1 \
/sys/class/qcom-battery/battery_charging_enabled,start=1,stop=0 \
/sys/class/qcom-battery/charging_suspend_battery,start=0,stop=1 \
/sys/class/asuslib/charger_limit_en,start=0,stop=1 \
/sys/class/asuslib/charging_suspend_en,start=0,stop=1 \
/sys/class/hw_power/charger/charge_data/enable_charger,start=1,stop=0 \
/sys/class/power_supply/idt/pin_enabled,start=1,stop=0 \
/sys/devices/platform/huawei_charger/enable_charger,start=1,stop=0 \
/sys/devices/platform/lge-unified-nodes/charging_enable,start=1,stop=0 \
/sys/devices/platform/lge-unified-nodes/charging_completed,start=0,stop=1 \
/sys/devices/platform/mt-battery/disable_charger,start=0,stop=1 \
/sys/devices/platform/battery/ChargerEnable,start=1,stop=0 \
/sys/devices/platform/soc/soc:google,charger/charge_disable,start=0,stop=1 \
/sys/devices/platform/charger/bypass_charger,start=0,stop=1 \
/sys/devices/platform/soc/soc:qcom,pmic_glink/soc:qcom,pmic_glink:qcom,battery_charger/force_charger_suspend,start=0,stop=1 \
/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable,start=1,stop=0 \
/sys/kernel/debug/google_charger/chg_suspend,start=0,stop=1 \
/sys/kernel/debug/google_charger/input_suspend,start=0,stop=1 \
/sys/kernel/debug/google_charger/chg_mode,start=1,stop=0 \
/sys/kernel/nubia_charge/charger_bypass,start=off,stop=on \
/sys/module/qpnp_adaptive_charge/parameters/blocking,start=0,stop=1 \
/proc/driver/charger_limit_enable,start=0,stop=1 \
/proc/driver/charger_limit,start=100,stop=1 \
/proc/mtk_battery_cmd/current_cmd,start=0_0,stop=0_1 \
/proc/mtk_battery_cmd/en_power_path,start=1,stop=0 \
/sys/class/power_supply/ac/device/power_supply/usb/power_switch,start=1,stop=0 \
/sys/devices/platform/soc/soc:mca_business_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/soc:mca_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/soc@0:mca_business_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/soc@0:mca_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/mca_business_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/mca_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc@0/soc:mca_business_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc@0/soc:mca_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc@0/mca_business_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc@0/mca_charger/handle_state,start=0,stop=1 \
/sys/class/power_supply/mca-charger/handle_state,start=0,stop=1 \
/sys/class/power_supply/mca_charger/handle_state,start=0,stop=1 \
/sys/devices/platform/soc/soc:mca_business_charger/stop_handle_charge,start=0,stop=1 \
/sys/devices/platform/soc/soc:mca_charger/stop_handle_charge,start=0,stop=1 \
/sys/devices/platform/soc@0/soc:mca_business_charger/stop_handle_charge,start=0,stop=1 \
/sys/devices/platform/soc@0/soc:mca_charger/stop_handle_charge,start=0,stop=1"

# 仅当常规开关全部写失败时才试：电流墙 / 端口 suspend（易与快充协商打架，故置后）
QSC_LAST_RESORT_SWITCHES="\
/sys/class/power_supply/battery/constant_charge_current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/input_current_max,start=3000000,stop=0 \
/sys/class/power_supply/battery/fast_charge_current_max,start=3000000,stop=0 \
/sys/class/power_supply/usb/input_suspend,start=0,stop=1 \
/sys/class/power_supply/qc_usb/input_suspend,start=0,stop=1 \
/sys/class/power_supply/dc/input_suspend,start=0,stop=1 \
/sys/class/power_supply/wireless/input_suspend,start=0,stop=1 \
/sys/class/power_supply/pc_port/input_suspend,start=0,stop=1 \
/sys/class/power_supply/battery/charge_type,start=Fast,stop=None"

QSC_USER_SWITCHES=""
