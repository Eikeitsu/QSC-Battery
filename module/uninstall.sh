#!/system/bin/sh

MODDIR=${0%/*}

# 卸载前尝试恢复充电（若模块曾触发停充）
if [ -f "$MODDIR/data/power_switch" ] && [ -f "$MODDIR/bin/qsc_switch.sh" ]; then
	. "$MODDIR/bin/common.sh" 2>/dev/null
	if [ -f "$LIST_SWITCH" ]; then
		switch_list="$(cat "$LIST_SWITCH")"
		for i in $switch_list; do
			route="$(echo "$i" | sed -n 's/,start=.*//g;$p')"
			if [ -f "$route" ]; then
				start_val="$(echo "$i" | sed -n 's/.*,start=//g;s/,stop=.*//g;s/_/ /g;$p')"
				echo "$start_val" > "$route" 2>/dev/null
			fi
		done
	fi
	for mca in /sys/devices/platform/soc/soc:mca_business_charger/handle_state \
	           /sys/devices/platform/soc/soc:mca_charger/handle_state \
	           /sys/devices/platform/soc/soc@0:mca_business_charger/handle_state \
	           /sys/devices/platform/soc/soc@0:mca_charger/handle_state \
	           /sys/devices/platform/soc/mca_business_charger/handle_state \
	           /sys/devices/platform/soc/mca_charger/handle_state \
	           /sys/class/power_supply/mca-charger/handle_state \
	           /sys/class/power_supply/mca_charger/handle_state \
	           /sys/class/power_supply/mca-battery/handle_state \
	           /sys/class/power_supply/mca_battery/handle_state; do
		if [ -f "$mca" ]; then
			chmod 0644 "$mca" 2>/dev/null
			echo "0" > "$mca" 2>/dev/null
		fi
	done
fi

echo "$(date +%F_%T) 模块已卸载" >> /sdcard/qsc_uninstall.log 2>/dev/null
