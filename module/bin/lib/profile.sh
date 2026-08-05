#!/system/bin/sh
# 本机充电能力探测 → data/device.profile（按节点存在动态启用，不绑机型名）

QSC_MCA_CANDIDATES="\
/sys/devices/platform/soc/soc:mca_business_charger/handle_state \
/sys/devices/platform/soc/soc:mca_charger/handle_state \
/sys/devices/platform/soc/soc@0:mca_business_charger/handle_state \
/sys/devices/platform/soc/soc@0:mca_charger/handle_state \
/sys/devices/platform/soc/mca_business_charger/handle_state \
/sys/devices/platform/soc/mca_charger/handle_state \
/sys/class/power_supply/mca-charger/handle_state \
/sys/class/power_supply/mca_charger/handle_state \
/sys/class/power_supply/mca-battery/handle_state \
/sys/class/power_supply/mca_battery/handle_state"

qsc_find_mca_path() {
	local path
	for path in $QSC_MCA_CANDIDATES; do
		if [ -f "$path" ]; then
			echo "$path"
			return 0
		fi
	done
	path="$(find /sys/devices/platform/ -maxdepth 8 -type f -name 'handle_state' \( -path '*mca*' -o -path '*charg*' \) 2>/dev/null | head -n 1)"
	if [ -n "$path" ] && [ -f "$path" ]; then
		echo "$path"
		return 0
	fi
	return 1
}

qsc_write_device_profile() {
	local mca_path="$1"
	local mca=0
	local reassert=0
	local pref_path pref_start pref_stop pref_at
	mkdir -p "$DATADIR" 2>/dev/null
	# 重新探测 MCA 时保留已测出的首选开关
	pref_path="$(qsc_profile_get preferred_switch 2>/dev/null)"
	pref_start="$(qsc_profile_get preferred_start 2>/dev/null)"
	pref_stop="$(qsc_profile_get preferred_stop 2>/dev/null)"
	pref_at="$(qsc_profile_get preferred_tested_at 2>/dev/null)"
	if [ -n "$mca_path" ] && [ -f "$mca_path" ]; then
		mca=1
		reassert=1
	else
		mca_path=""
	fi
	# 已测出首选开关时也保持重申
	if [ -n "$pref_path" ]; then
		reassert=1
	fi
	cat > "$DEVICE_PROFILE" << EOF
# QSC device.profile — 由本机节点探测生成，勿手改除非清楚含义
mca=$mca
mca_path=$mca_path
mca_stop=1
mca_start=0
reassert=$reassert
preferred_switch=$pref_path
preferred_start=$pref_start
preferred_stop=$pref_stop
preferred_tested_at=$pref_at
model=$(getprop ro.product.model 2>/dev/null)
device=$(getprop ro.product.device 2>/dev/null)
marketname=$(getprop ro.product.marketname 2>/dev/null)
board=$(getprop ro.product.board 2>/dev/null)
platform=$(getprop ro.board.platform 2>/dev/null)
detected_at=$(date +%F_%T)
EOF
}

# stdout 摘要；返回 0=有 MCA，1=无
qsc_detect_and_write_profile() {
	local mca_path=""
	mkdir -p "$DATADIR" 2>/dev/null
	mca_path="$(qsc_find_mca_path)" || mca_path=""
	qsc_write_device_profile "$mca_path"
	if [ -n "$mca_path" ]; then
		echo "MCA=1 path=$mca_path"
		return 0
	fi
	echo "MCA=0 （未发现 handle_state，使用通用停充节点）"
	return 1
}

qsc_profile_get() {
	local key="$1"
	[ -f "$DEVICE_PROFILE" ] || return 1
	sed -n "s/^${key}=//p" "$DEVICE_PROFILE" | head -n 1 | tr -d '\r'
}

qsc_profile_set_key() {
	local key="$1"
	local val="$2"
	local tmp
	[ -f "$DEVICE_PROFILE" ] || qsc_write_device_profile ""
	tmp="$DEVICE_PROFILE.tmp.$$"
	if grep -q "^${key}=" "$DEVICE_PROFILE" 2>/dev/null; then
		sed "s|^${key}=.*|${key}=${val}|" "$DEVICE_PROFILE" >"$tmp" && mv -f "$tmp" "$DEVICE_PROFILE"
	else
		echo "${key}=${val}" >>"$DEVICE_PROFILE"
	fi
	chmod 0644 "$DEVICE_PROFILE" 2>/dev/null
}

qsc_set_preferred_switch() {
	local path="$1"
	local start="$2"
	local stop="$3"
	mkdir -p "$DATADIR" 2>/dev/null
	[ -f "$DEVICE_PROFILE" ] || qsc_detect_and_write_profile >/dev/null 2>&1 || true
	qsc_profile_set_key preferred_switch "$path"
	qsc_profile_set_key preferred_start "$start"
	qsc_profile_set_key preferred_stop "$stop"
	qsc_profile_set_key preferred_tested_at "$(date +%F_%T)"
	# 有实测首选时启用重申
	qsc_profile_set_key reassert 1
}

qsc_clear_preferred_switch() {
	[ -f "$DEVICE_PROFILE" ] || return 0
	qsc_profile_set_key preferred_switch ""
	qsc_profile_set_key preferred_start ""
	qsc_profile_set_key preferred_stop ""
	qsc_profile_set_key preferred_tested_at ""
}

# 加载到 QSC_MCA / QSC_MCA_PATH / QSC_MCA_STOP / QSC_MCA_START / QSC_REASSERT
# 以及 QSC_PREF_PATH / QSC_PREF_START / QSC_PREF_STOP
qsc_load_device_profile() {
	QSC_MCA=0
	QSC_MCA_PATH=""
	QSC_MCA_STOP=1
	QSC_MCA_START=0
	QSC_REASSERT=0
	QSC_PREF_PATH=""
	QSC_PREF_START=""
	QSC_PREF_STOP=""
	if [ ! -f "$DEVICE_PROFILE" ]; then
		qsc_detect_and_write_profile >/dev/null 2>&1 || true
	fi
	[ -f "$DEVICE_PROFILE" ] || return 1
	QSC_MCA="$(qsc_profile_get mca)"
	QSC_MCA_PATH="$(qsc_profile_get mca_path)"
	QSC_MCA_STOP="$(qsc_profile_get mca_stop)"
	QSC_MCA_START="$(qsc_profile_get mca_start)"
	QSC_REASSERT="$(qsc_profile_get reassert)"
	QSC_PREF_PATH="$(qsc_profile_get preferred_switch)"
	QSC_PREF_START="$(qsc_profile_get preferred_start)"
	QSC_PREF_STOP="$(qsc_profile_get preferred_stop)"
	case "$QSC_MCA" in 1) ;; *) QSC_MCA=0 ;; esac
	case "$QSC_REASSERT" in 1) ;; *) QSC_REASSERT=0 ;; esac
	[ -n "$QSC_MCA_STOP" ] || QSC_MCA_STOP=1
	[ -n "$QSC_MCA_START" ] || QSC_MCA_START=0
	if [ -n "$QSC_PREF_PATH" ] && [ ! -f "$QSC_PREF_PATH" ]; then
		QSC_PREF_PATH=""
		QSC_PREF_START=""
		QSC_PREF_STOP=""
	fi
	if [ "$QSC_MCA" = "1" ] && [ -n "$QSC_MCA_PATH" ] && [ ! -f "$QSC_MCA_PATH" ]; then
		qsc_detect_and_write_profile >/dev/null 2>&1 || true
		QSC_MCA="$(qsc_profile_get mca)"
		QSC_MCA_PATH="$(qsc_profile_get mca_path)"
		QSC_REASSERT="$(qsc_profile_get reassert)"
		QSC_PREF_PATH="$(qsc_profile_get preferred_switch)"
		QSC_PREF_START="$(qsc_profile_get preferred_start)"
		QSC_PREF_STOP="$(qsc_profile_get preferred_stop)"
		case "$QSC_MCA" in 1) ;; *) QSC_MCA=0 ;; esac
		case "$QSC_REASSERT" in 1) ;; *) QSC_REASSERT=0 ;; esac
		if [ -n "$QSC_PREF_PATH" ] && [ ! -f "$QSC_PREF_PATH" ]; then
			QSC_PREF_PATH=""
			QSC_PREF_START=""
			QSC_PREF_STOP=""
		fi
	fi
	return 0
}
