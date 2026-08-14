#!/system/bin/sh
. "${0%/*}/common.sh"

# 扫描常见停充节点
# 先写临时文件，非空再替换正式列表，避免扫描失败清空旧结果
_QSC_LIST_SWITCH_FINAL="$LIST_SWITCH"
LIST_SWITCH="$DATADIR/.list_switch_build"
rm -f "$LIST_SWITCH"
# suspend / disable 类：停充写 1，恢复写 0
find /sys/*/* -type f \( \
	-iname "*input_suspend" -o -iname "*battery_input_suspend" -o \
	-iname "*disable*_charge*" -o -iname "*charge*_disable*" -o \
	-iname "*disable*_charging*" -o -iname "*stop_charge*" -o \
	-iname "*stop_charging*" -o -iname "*stop_handle_charge" -o \
	-iname "*batt_slate_mode" -o -iname "*store_mode" -o \
	-iname "*night_charging" -o -iname "*force_disable_charging" -o \
	-iname "*op_disable_charge" -o -iname "*charge_disable" -o \
	-iname "*cool_mode" -o -iname "*batt_protect*" -o \
	-iname "*charging_suspend*" -o -iname "*charger_limit_en" -o \
	-iname "*force_charger_suspend" -o -iname "*force_usb_suspend" -o \
	-iname "*bypass_charger" \
	\) 2>/dev/null \
	| egrep -i -v 'limit_max|float|step|reverse|/battery_|bq2597x|/cpu/|firmware|charge_control_limit' \
	| sed -n 's/$/,start=0,stop=1/g;p' >"$LIST_SWITCH"

# enable 类：停充写 0，恢复写 1
find /sys/*/* -type f \( \
	-iname "*charging_enable*" -o -iname "*enable*_charge*" -o \
	-iname "*charge*_enable*" -o -iname "*enable*_charging*" -o \
	-iname "*charger_control" -o -iname "*ChargerEnable" -o \
	-iname "*chg_enable" -o -iname "mi_charge_enable" \
	\) 2>/dev/null \
	| egrep -i -v 'limit|prohibit|prevent|disable|stop|restrict|reverse|max|float|step|/battery_|bq2597x|/cpu/|firmware' \
	| sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"

# enable 名但语义为禁止类
find /sys/*/* -type f \( \
	-iname "*charging_enable*" -o -iname "*enable*_charge*" -o \
	-iname "*charge*_enable*" -o -iname "*enable*_charging*" \
	\) 2>/dev/null \
	| egrep -i 'prohibit|prevent|disable|stop|restrict' \
	| egrep -i -v 'limit|max|float|step|reverse|/battery_|bq2597x|/cpu/|firmware' \
	| sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"

# power_supply 常规开关（不含 charge_control_limit，极性因机而异）
find /sys/class/power_supply/*/ -maxdepth 1 -type f \( \
	-iname "*charging_enabled" -o -iname "*battery_charging_enabled" -o \
	-iname "*charge_enabled" -o -iname "*charge_disable" -o \
	-iname "*disable_charging" -o -iname "*charging_disable" -o \
	-iname "*stop_charging" -o -iname "*op_disable_charge" \
	\) 2>/dev/null | while read -r f; do
	case "$f" in
		*disable*|*stop_charging)
			echo "${f},start=0,stop=1"
			;;
		*)
			echo "${f},start=1,stop=0"
			;;
	esac
done >>"$LIST_SWITCH"

# qcom-battery：enable 与 suspend 极性分开（勿统一写成 start=1）
find /sys/class/qcom-battery/ -maxdepth 1 -type f \( \
	-iname "*charging_enabled" -o -iname "*charge_enabled" -o \
	-iname "*battery_charging_enabled" \
	\) 2>/dev/null | sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"
find /sys/class/qcom-battery/ -maxdepth 1 -type f \( \
	-iname "*input_suspend" -o -iname "*charge_disable" -o \
	-iname "*disable_charging" -o -iname "*night_charging" -o \
	-iname "*cool_mode" -o -iname "*batt_protect*" -o \
	-iname "*charging_suspend*" \
	\) 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"

# ASUS / 华为 / LGE / MTK / Google / Nubia / OPLUS
find /sys/class/asuslib/ -maxdepth 1 -type f \( \
	-iname "charger_limit_en" -o -iname "charging_suspend_en" \
	\) 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"
find /sys/class/battchg_ext/ -maxdepth 1 -type f \( \
	-iname "*charge_disable*" -o -iname "*input_suspend*" \
	\) 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"
find /sys/class/hw_power/charger/charge_data/ -maxdepth 1 -type f -iname "enable_charger" 2>/dev/null \
	| sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"
find /sys/devices/platform/huawei_charger/ -maxdepth 1 -type f -iname "enable_charger" 2>/dev/null \
	| sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"
find /sys/devices/platform/lge-unified-nodes/ -maxdepth 1 -type f \( \
	-iname "charging_enable" -o -iname "charging_completed" \
	\) 2>/dev/null | while read -r f; do
	case "$f" in
		*completed) echo "${f},start=0,stop=1" ;;
		*) echo "${f},start=1,stop=0" ;;
	esac
done >>"$LIST_SWITCH"
find /sys/devices/platform/mt-battery/ -maxdepth 1 -type f -iname "disable_charger" 2>/dev/null \
	| sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"
find /sys/devices/platform/ -maxdepth 4 -type f \( \
	-iname "charge_disable" -o -iname "bypass_charger" -o \
	-iname "force_charger_suspend" -o -iname "force_usb_suspend" \
	\) 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"
find /sys/devices/platform/ -maxdepth 6 -type f \( \
	-iname "*charging_enable*" -o -iname "chg_enable" -o -iname "ChargerEnable" \
	\) \( -path "*oplus*" -o -path "*lge*" -o -path "*battery*" \) 2>/dev/null \
	| sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"
find /sys/devices/virtual/oplus_chg/ -maxdepth 3 -type f -iname "*charging_enable*" 2>/dev/null \
	| sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"
find /sys/kernel/nubia_charge/ -maxdepth 1 -type f -iname "charger_bypass" 2>/dev/null \
	| sed -n 's/$/,start=off,stop=on/g;p' >>"$LIST_SWITCH"
find /sys/kernel/debug/google_charger/ -maxdepth 1 -type f \( \
	-iname "chg_suspend" -o -iname "input_suspend" \
	\) 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"
find /sys/kernel/debug/google_charger/ -maxdepth 1 -type f -iname "chg_mode" 2>/dev/null \
	| sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"

# MCA / 骁龙商务充
find /sys/devices/platform/soc/ -maxdepth 5 -type f -name "handle_state" -path "*mca*" 2>/dev/null \
	| sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"
find /sys/devices/platform/soc/ -maxdepth 5 -type f -name "handle_state" -path "*charg*" 2>/dev/null \
	| sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"
find /sys/devices/platform/ -maxdepth 6 -type f -name "handle_state" 2>/dev/null \
	| sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"
find /sys/devices/platform/soc/ -maxdepth 5 -type f \( \
	-iname "force_charging" -o -iname "enable_charging" -o -iname "charge_control" \
	\) -path "*mca*" 2>/dev/null | sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"

# 电流墙型「伪开关」（无专用开关时的兜底）
find /sys/class/power_supply/ -maxdepth 2 -type f \( \
	-iname "constant_charge_current_max" -o -iname "current_max" -o \
	-iname "input_current_max" -o -iname "charge_current" -o \
	-iname "fast_charge_current_max" \
	\) 2>/dev/null | sed -n 's/$/,start=3000000,stop=0/g;p' >>"$LIST_SWITCH"

find /sys/class/power_supply/battery/ -maxdepth 1 -type f -iname "charge_type" 2>/dev/null \
	| sed -n 's/$/,start=Fast,stop=None/g;p' >>"$LIST_SWITCH"
find /sys/class/power_supply/ -maxdepth 2 -type f -iname "*charge_control_enabled" 2>/dev/null \
	| sed -n 's/$/,start=1,stop=0/g;p' >>"$LIST_SWITCH"
find /sys/class/power_supply/usb/ /sys/class/power_supply/qc_usb/ /sys/class/power_supply/dc/ \
	/sys/class/power_supply/wireless/ /sys/class/power_supply/pc_port/ -maxdepth 1 \
	-type f -iname "input_suspend" 2>/dev/null | sed -n 's/$/,start=0,stop=1/g;p' >>"$LIST_SWITCH"

# charging_state：enabled / disabled（ACC）
find /sys/devices/ -maxdepth 6 -type f -iname "charging_state" 2>/dev/null \
	| sed -n 's/$/,start=enabled,stop=disabled/g;p' >>"$LIST_SWITCH"

# list_charge_current：收集 *restrict*_cur* 作限流补充节点（排除 usb）
: >"${LIST_CHARGE_CURRENT:-$DATADIR/list_charge_current}"
find /sys/ -name '*restrict*_cur*' 2>/dev/null \
	| egrep -i -v 'usb' \
	| sort -u >"${LIST_CHARGE_CURRENT:-$DATADIR/list_charge_current}"

# 电流节点探测（充电时才有可信读数；未在充则保留旧列表）
if [ -f "${0%/*}/list_curr.sh" ]; then
	chmod 0755 "${0%/*}/list_curr.sh" 2>/dev/null
	"${0%/*}/list_curr.sh" >/dev/null 2>&1 || true
fi

# 硬编码兜底：常见路径（存在才写）
cat >>"$LIST_SWITCH" << 'EOF'
/sys/class/power_supply/battery/charging_enabled,start=1,stop=0
/sys/class/power_supply/battery/battery_charging_enabled,start=1,stop=0
/sys/class/power_supply/battery/batt_charging_enabled,start=1,stop=0
/sys/class/power_supply/battery/charge_charger_state,start=1,stop=0
/sys/class/power_supply/battery/connect_disable,start=0,stop=1
/sys/class/power_supply/battery/batt_slate_mode,start=0,stop=1
/sys/class/power_supply/battery/store_mode,start=0,stop=1
/sys/class/power_supply/battery/input_suspend,start=0,stop=1
/sys/class/power_supply/battery/battery_input_suspend,start=0,stop=1
/sys/class/power_supply/battery/night_charging,start=0,stop=1
/sys/class/power_supply/battery/charge_disable,start=0,stop=1
/sys/class/power_supply/battery/disable_charging,start=0,stop=1
/sys/class/power_supply/battery/stop_charging,start=0,stop=1
/sys/class/power_supply/battery/charge_enabled,start=1,stop=0
/sys/class/power_supply/battery/op_disable_charge,start=0,stop=1
/sys/class/power_supply/battery/device/Charging_Enable,start=1,stop=0
/sys/class/power_supply/battery/ChargerEnable,start=1,stop=0
/sys/class/power_supply/battery/force_disable_charging,start=0,stop=1
/sys/class/power_supply/battery/charge_control_enabled,start=1,stop=0
/sys/class/power_supply/battery/mi_charge_enable,start=1,stop=0
/sys/class/power_supply/battery_ext/smart_charging_interruption,start=0,stop=1
/sys/class/power_supply/main/adapter_cc_mode,start=0,stop=1
/sys/class/power_supply/main/cool_mode,start=0,stop=1
/sys/class/power_supply/charger/charge_disable,start=0,stop=1
/sys/class/power_supply/bms/charge_disable,start=0,stop=1
/sys/class/power_supply/bms/charging_enabled,start=1,stop=0
/sys/class/power_supply/bms/charge_enabled,start=1,stop=0
/sys/class/power_supply/mi_chg/charge_disable,start=0,stop=1
/sys/class/power_supply/mi_chg/charging_enabled,start=1,stop=0
/sys/class/power_supply/idt/pin_enabled,start=1,stop=0
/sys/class/qcom-battery/charging_enabled,start=1,stop=0
/sys/class/qcom-battery/charge_disable,start=0,stop=1
/sys/class/qcom-battery/input_suspend,start=0,stop=1
/sys/class/qcom-battery/battery_charging_enabled,start=1,stop=0
/sys/class/qcom-battery/charging_suspend_battery,start=0,stop=1
/sys/class/qcom-battery/night_charging,start=0,stop=1
/sys/class/qcom-battery/cool_mode,start=0,stop=1
/sys/class/qcom-battery/batt_protect_en,start=0,stop=1
/sys/class/asuslib/charger_limit_en,start=0,stop=1
/sys/class/asuslib/charging_suspend_en,start=0,stop=1
/sys/class/hw_power/charger/charge_data/enable_charger,start=1,stop=0
/sys/devices/platform/huawei_charger/enable_charger,start=1,stop=0
/sys/devices/platform/lge-unified-nodes/charging_enable,start=1,stop=0
/sys/devices/platform/lge-unified-nodes/charging_completed,start=0,stop=1
/sys/devices/platform/mt-battery/disable_charger,start=0,stop=1
/sys/devices/platform/battery/ChargerEnable,start=1,stop=0
/sys/devices/platform/soc/soc:google,charger/charge_disable,start=0,stop=1
/sys/devices/platform/charger/bypass_charger,start=0,stop=1
/sys/devices/platform/soc/soc:qcom,pmic_glink/soc:qcom,pmic_glink:qcom,battery_charger/force_charger_suspend,start=0,stop=1
/sys/devices/virtual/oplus_chg/battery/mmi_charging_enable,start=1,stop=0
/sys/kernel/debug/google_charger/chg_suspend,start=0,stop=1
/sys/kernel/debug/google_charger/input_suspend,start=0,stop=1
/sys/kernel/debug/google_charger/chg_mode,start=1,stop=0
/sys/kernel/nubia_charge/charger_bypass,start=off,stop=on
/sys/module/qpnp_adaptive_charge/parameters/blocking,start=0,stop=1
/sys/class/power_supply/usb/input_suspend,start=0,stop=1
/sys/class/power_supply/qc_usb/input_suspend,start=0,stop=1
/sys/class/power_supply/dc/input_suspend,start=0,stop=1
/sys/class/power_supply/wireless/input_suspend,start=0,stop=1
/sys/class/power_supply/pc_port/input_suspend,start=0,stop=1
/sys/class/power_supply/ac/device/power_supply/usb/power_switch,start=1,stop=0
/sys/class/power_supply/ac/device/power_supply/usb/input_suspend,start=0,stop=1
/sys/class/power_supply/battery/constant_charge_current_max,start=3000000,stop=0
/sys/class/power_supply/battery/current_max,start=3000000,stop=0
/sys/class/power_supply/battery/input_current_max,start=3000000,stop=0
/sys/class/power_supply/battery/charge_current,start=3000000,stop=0
/sys/class/power_supply/battery/fast_charge_current_max,start=3000000,stop=0
/sys/class/power_supply/battery/charge_control_end_threshold,start=100,stop=0
/sys/class/power_supply/battery/charge_type,start=Fast,stop=None
/proc/driver/charger_limit_enable,start=0,stop=1
/proc/driver/charger_limit,start=100,stop=1
/proc/mtk_battery_cmd/current_cmd,start=0_0,stop=0_1
/proc/mtk_battery_cmd/en_power_path,start=1,stop=0
EOF

if [ -f "$LIST_SWITCH" ]; then
	sort -u "$LIST_SWITCH" -o "$LIST_SWITCH"
fi
if [ -s "$LIST_SWITCH" ]; then
	mv -f "$LIST_SWITCH" "$_QSC_LIST_SWITCH_FINAL"
	n="$(wc -l <"$_QSC_LIST_SWITCH_FINAL" | tr -d ' ')"
	echo "[QSC] list_switch.sh 执行完毕，已生成节点列表: $_QSC_LIST_SWITCH_FINAL" >&2
	qsc_log debug "开关扫描完成，$n 条节点"
else
	rm -f "$LIST_SWITCH"
	echo "[QSC] list_switch.sh 扫描结果为空，保留原列表: $_QSC_LIST_SWITCH_FINAL" >&2
	if [ -s "$_QSC_LIST_SWITCH_FINAL" ]; then
		qsc_log warn "开关扫描结果为空，已保留旧列表"
	else
		qsc_log error "开关扫描结果为空且无旧列表"
	fi
fi
# ##
