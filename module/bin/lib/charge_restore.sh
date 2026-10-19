#!/system/bin/sh
# charge: restore switches / MCA charge
qsc_restore_switches_from_list() {
	local i route start_val
	[ -f "$LIST_SWITCH" ] || return 1
	for i in $(cat "$LIST_SWITCH"); do
		qsc_parse_normalized_switch_entry "$i" || continue
		route="$QSC_SW_ROUTE"
		if [ -f "$route" ]; then
			start_val="$QSC_SW_START"
			case "$start_val" in
				*_*) start_val="$(printf '%s' "$start_val" | tr '_' ' ')" ;;
			esac
			echo "$start_val" > "$route" 2>/dev/null
		fi
	done
}

qsc_restore_mca_charge() {
	local mca
	qsc_load_device_profile 2>/dev/null || true
	if [ -n "$QSC_MCA_PATH" ] && [ -f "$QSC_MCA_PATH" ]; then
		qsc_mca_raw_echo "$QSC_MCA_PATH" "${QSC_MCA_START:-0}"
		return 0
	fi
	for mca in $QSC_MCA_CANDIDATES $QSC_MCA_STOP_HANDLE_CANDIDATES; do
		if [ -f "$mca" ]; then
			qsc_mca_raw_echo "$mca" "0"
		fi
	done
}
