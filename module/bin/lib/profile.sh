#!/system/bin/sh
# 本机充电能力探测 → data/device.profile（按节点存在动态启用，不绑机型名）

# 优先 business_charger（小米17 等），再 mca_charger（K90 / K90U 等）
# 含 soc@0 嵌套路径（部分 HyperOS 不在 soc/soc:xxx 直挂）
QSC_MCA_CANDIDATES="\
/sys/devices/platform/soc/soc:mca_business_charger/handle_state \
/sys/devices/platform/soc/soc:mca_charger/handle_state \
/sys/devices/platform/soc/soc@0:mca_business_charger/handle_state \
/sys/devices/platform/soc/soc@0:mca_charger/handle_state \
/sys/devices/platform/soc/mca_business_charger/handle_state \
/sys/devices/platform/soc/mca_charger/handle_state \
/sys/devices/platform/soc@0/soc:mca_business_charger/handle_state \
/sys/devices/platform/soc@0/soc:mca_charger/handle_state \
/sys/devices/platform/soc@0/mca_business_charger/handle_state \
/sys/devices/platform/soc@0/mca_charger/handle_state \
/sys/class/power_supply/mca-charger/handle_state \
/sys/class/power_supply/mca_charger/handle_state \
/sys/class/power_supply/mca-battery/handle_state \
/sys/class/power_supply/mca_battery/handle_state"

# 部分机型另有 stop_handle_charge（极性同 handle_state：停=1 开=0）
QSC_MCA_STOP_HANDLE_CANDIDATES="\
/sys/devices/platform/soc/soc:mca_business_charger/stop_handle_charge \
/sys/devices/platform/soc/soc:mca_charger/stop_handle_charge \
/sys/devices/platform/soc/soc@0:mca_business_charger/stop_handle_charge \
/sys/devices/platform/soc/soc@0:mca_charger/stop_handle_charge \
/sys/devices/platform/soc/mca_business_charger/stop_handle_charge \
/sys/devices/platform/soc/mca_charger/stop_handle_charge \
/sys/devices/platform/soc@0/soc:mca_business_charger/stop_handle_charge \
/sys/devices/platform/soc@0/soc:mca_charger/stop_handle_charge \
/sys/devices/platform/soc@0/mca_business_charger/stop_handle_charge \
/sys/devices/platform/soc@0/mca_charger/stop_handle_charge"

# sysfs 属性在部分内核上 find -type f / test -f 会漏；用 -e/-r
qsc_mca_node_ok() {
	[ -n "$1" ] && [ -e "$1" ] && [ -r "$1" ]
}

# 在已知 soc 根下用 shell 通配扫一层（不依赖 find -path）
qsc_mca_glob_under() {
	local root="$1"
	local name="$2"
	local p
	[ -d "$root" ] || return 1
	for p in \
		"$root/soc:mca_business_charger/$name" \
		"$root/soc:mca_charger/$name" \
		"$root/mca_business_charger/$name" \
		"$root/mca_charger/$name" \
		"$root"/soc:*mca*business*/"$name" \
		"$root"/soc:*mca*charg*/"$name" \
		"$root"/*mca*business*/"$name" \
		"$root"/*mca*charg*/"$name"
	do
		if qsc_mca_node_ok "$p"; then
			echo "$p"
			return 0
		fi
	done
	return 1
}

qsc_find_mca_named() {
	# $1=handle_state|stop_handle_charge；优先 mca_business，再任意 mca
	local name="$1"
	local path root
	path="$(find /sys/devices/platform/ /sys/class/power_supply/ /sys/devices/virtual/ \
		-maxdepth 12 \( -name "$name" \) 2>/dev/null \
		| grep -F 'mca_business' | head -n 1)"
	if qsc_mca_node_ok "$path"; then
		echo "$path"
		return 0
	fi
	path="$(find /sys/devices/platform/ /sys/class/power_supply/ /sys/devices/virtual/ \
		-maxdepth 12 \( -name "$name" \) 2>/dev/null \
		| grep -F 'mca' | head -n 1)"
	if qsc_mca_node_ok "$path"; then
		echo "$path"
		return 0
	fi
	# 无 mca 字样时不采信任意 charg*/handle_state，避免误伤其它 charger
	return 1
}

qsc_find_mca_path() {
	local path root
	for path in $QSC_MCA_CANDIDATES; do
		if qsc_mca_node_ok "$path"; then
			echo "$path"
			return 0
		fi
	done
	# soc / soc@N 通配（K90U 等可能挂在 soc@0 下）
	for root in /sys/devices/platform/soc /sys/devices/platform/soc@0 \
		/sys/devices/platform/soc@1 /sys/devices/platform/soc@*
	do
		path="$(qsc_mca_glob_under "$root" handle_state)" || path=""
		if qsc_mca_node_ok "$path"; then
			echo "$path"
			return 0
		fi
	done
	path="$(qsc_find_mca_named handle_state)" || path=""
	if qsc_mca_node_ok "$path"; then
		echo "$path"
		return 0
	fi
	# 仅有 stop_handle_charge 也视为 MCA（极性同 handle_state）
	for path in $QSC_MCA_STOP_HANDLE_CANDIDATES; do
		if qsc_mca_node_ok "$path"; then
			echo "$path"
			return 0
		fi
	done
	for root in /sys/devices/platform/soc /sys/devices/platform/soc@0 \
		/sys/devices/platform/soc@1 /sys/devices/platform/soc@*
	do
		path="$(qsc_mca_glob_under "$root" stop_handle_charge)" || path=""
		if qsc_mca_node_ok "$path"; then
			echo "$path"
			return 0
		fi
	done
	path="$(qsc_find_mca_named stop_handle_charge)" || path=""
	if qsc_mca_node_ok "$path"; then
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
	if qsc_mca_node_ok "$mca_path"; then
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
	# 便于社区反馈：有 mca 目录却无节点 vs 目录都没有
	_mca_dirs="$(ls -d /sys/devices/platform/soc*/*mca* \
		/sys/devices/platform/soc*/*/*mca* \
		/sys/class/power_supply/*mca* 2>/dev/null | head -n 3 | tr '\n' ' ')"
	if [ -n "$_mca_dirs" ]; then
		echo "MCA=0 （有 mca 目录但无 handle_state/stop_handle_charge，使用通用停充；dirs=${_mca_dirs}）"
	else
		echo "MCA=0 （未发现 handle_state/stop_handle_charge，使用通用停充节点）"
	fi
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
	if [ -n "$QSC_PREF_PATH" ] && ! qsc_mca_node_ok "$QSC_PREF_PATH"; then
		# preferred 也可能是非 MCA 节点；仅用 -e 判断仍合理
		if [ ! -e "$QSC_PREF_PATH" ]; then
			QSC_PREF_PATH=""
			QSC_PREF_START=""
			QSC_PREF_STOP=""
		fi
	fi
	# 路径失效或开机早期未就绪：实时重探（小米17/K90U 等 MCA 常晚于 service 启动出现）
	if [ -z "$QSC_MCA_PATH" ] || ! qsc_mca_node_ok "$QSC_MCA_PATH"; then
		_live="$(qsc_find_mca_path 2>/dev/null)" || _live=""
		if qsc_mca_node_ok "$_live"; then
			QSC_MCA=1
			QSC_MCA_PATH="$_live"
			QSC_MCA_STOP=1
			QSC_MCA_START=0
			QSC_REASSERT=1
			qsc_write_device_profile "$_live" >/dev/null 2>&1 || true
		else
			QSC_MCA=0
			QSC_MCA_PATH=""
		fi
	fi
	return 0
}
