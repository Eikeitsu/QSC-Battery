#!/system/bin/sh
# power_saver: skip / description
qsc_ps_can_skip_round() {
	local now last gap
	[ "${QSC_PS_ENABLE:-1}" = "1" ] || return 1
	# 模块关闭时也别空转，但仍要走满轮以刷新简介
	[ -f "$DATADIR/power_switch" ] && return 1
	qsc_ps_plugged && return 1

	now="${1:-0}"
	last="${QSC_PS_LAST_FULL:-0}"
	gap="${QSC_PS_FULL_MAX_GAP:-1800}"
	case "$gap" in ""|*[!0-9]*) gap=1800 ;; esac
	if [ "$now" -gt 0 ] 2>/dev/null && [ "$((now - last))" -ge "$gap" ] 2>/dev/null; then
		return 1
	fi
	return 0
}

# 省电路径下的简介刷新。
# 跳过整轮时 qsc_switch.sh 不会跑，而简介只在满轮里刷新，未插电时最长要等
# QSC_PS_FULL_MAX_GAP 才动一次，管理器里看着像电量/温度卡住了。
# 优先复用统一电池快照，只有 sysfs 不完整时才走 dumpsys 兜底；仅在显示值变化时
# 真正改写 module.prop。温度待机时会在两三度间来回抖，只靠「值变了就写」会变成
# 每 30 秒改一次 prop，所以再压一道最小间隔：省电的关键是别唤醒 CPU、别乱写盘。
# 无人打开模块管理器时：跳过纯电量/温度更新，仅状态突变才写；观看中缩短间隔。
QSC_PS_DESC_SIG=""
QSC_PS_DESC_STATE_SIG=""
QSC_PS_DESC_TS=0
# 默认 5 分钟；管理器前台时临时压到约 45s；上升沿可设 QSC_PS_DESC_FORCE=1 绕过
QSC_PS_DESC_MIN_GAP=300
QSC_PS_DESC_FORCE=0

# 参数: 当前单调秒（service.sh 已经读过 /proc/uptime，不再重复读）
qsc_ps_refresh_desc() {
	local now="${1:-0}"
	local lv temp digits off plugged stopped sig state_sig p viewer=0 gap
	[ -f "$DATADIR/hot_update_fallback_reboot" ] && return 0
	if type qsc_ps_desc_suppressed >/dev/null 2>&1 && qsc_ps_desc_suppressed; then
		type qsc_description_restore_static >/dev/null 2>&1 &&
			qsc_description_restore_static
		return 0
	fi
	if ! qsc_description_enabled 2>/dev/null; then
		type qsc_description_restore_static >/dev/null 2>&1 &&
			qsc_description_restore_static
		return 0
	fi
	type qsc_refresh_module_description >/dev/null 2>&1 || return 0

	off=0
	if [ -f "$MODULE_OFF_FLAG" ] || [ -f "$MODDIR/disable" ]; then
		off=1
	fi
	stopped=0
	[ -f "$DATADIR/power_switch" ] && stopped=1
	plugged=0
	if type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
		plugged=1
	fi
	state_sig="${off}:${plugged}:${stopped}"

	if type qsc_manager_viewer_active >/dev/null 2>&1 && qsc_manager_viewer_active; then
		viewer=1
	fi

	# 无人看模块列表：仅状态类变化才继续；纯电量/温度抖动跳过（不停充满轮仍会写简介）
	if [ "$viewer" != "1" ]; then
		if [ -n "${QSC_PS_DESC_STATE_SIG:-}" ] &&
			[ "$state_sig" = "$QSC_PS_DESC_STATE_SIG" ]; then
			return 0
		fi
	fi

	gap="${QSC_PS_DESC_MIN_GAP:-300}"
	[ "$viewer" = "1" ] && [ "$gap" -gt 60 ] 2>/dev/null && gap=45
	if [ "${QSC_PS_DESC_FORCE:-0}" != "1" ] &&
		[ "$now" -gt 0 ] 2>/dev/null &&
		[ "$((now - QSC_PS_DESC_TS))" -lt "$gap" ] 2>/dev/null; then
		return 0
	fi

	lv=""
	temp=""
	if type qsc_battery_snapshot_read >/dev/null 2>&1; then
		# 与 qsc_switch.sh / WebUI 共用同一套 sysfs→dumpsys 兜底，
		# 避免「首次能读到，后续快路径却读不到」导致简介停在热更新后的数值。
		qsc_battery_snapshot_read >/dev/null 2>&1 || true
		# region agent log
		type qsc_runtime_trace >/dev/null 2>&1 &&
			qsc_runtime_trace "H2" "snapshot" \
				"${QSC_BATTERY_LEVEL:-}:${QSC_BATTERY_TEMP:-}:${QSC_BATTERY_STATUS:-}:${QSC_BATTERY_SOURCE:-}"
		# endregion
		lv="${QSC_BATTERY_LEVEL:-}"
		temp="${QSC_BATTERY_TEMP:-}"
		[ -n "${QSC_BATTERY_POWERED:-}" ] && plugged=1
	else
		# 兼容被裁剪、没有 battery_snapshot.sh 的旧安装包。
		for p in "$PSDIR/battery/capacity" \
			"$PSDIR/bms/capacity" \
			"$PSDIR/battery/soc"; do
			if qsc_ps_read "$p"; then
				case "$QSC_PS_VAL" in
					*[!0-9]*) ;;
					*) lv="$QSC_PS_VAL"; break ;;
				esac
			fi
		done

		for p in "$PSDIR/battery/temp" \
			"$PSDIR/bms/temp" \
			"$PSDIR/battery/batt_temp"; do
			qsc_ps_read "$p" && { temp="$QSC_PS_VAL"; break; }
		done
		if [ -n "$temp" ]; then
			digits="${temp#-}"
			case "$temp" in
				""|"-"|*[!0-9-]*) temp="" ;;
				*)
					case "$digits" in
						""|*[!0-9]*) temp="" ;;
						*)
							if [ "$digits" -ge 10000 ]; then
								temp=$((temp / 1000))
							elif [ "$digits" -ge 1000 ]; then
								temp=$((temp / 100))
							elif [ "$digits" -ge 100 ]; then
								temp=$((temp / 10))
							fi
							[ "$temp" -ge -20 ] && [ "$temp" -le 100 ] || temp=""
							;;
					esac
					;;
			esac
		fi
		qsc_ps_plugged && plugged=1
	fi

	state_sig="${off}:${plugged}:${stopped}"
	sig="${state_sig}:${lv}:${temp}"
	[ "$sig" = "$QSC_PS_DESC_SIG" ] && {
		QSC_PS_DESC_STATE_SIG="$state_sig"
		return 0
	}

	# 该函数也由 service.sh 在满轮前调用，不能假定一定是未插电。
	battery_level="$lv"
	temperature="$temp"
	battery_status="${QSC_BATTERY_STATUS:-}"
	battery_powered=""
	[ "$plugged" = "1" ] && battery_powered="powered: true"
	# region agent log
	qsc_refresh_module_description
	_desc_rc="$?"
	if [ "$_desc_rc" -eq 0 ]; then
		QSC_PS_DESC_SIG="$sig"
		QSC_PS_DESC_STATE_SIG="$state_sig"
		QSC_PS_DESC_TS="$now"
		QSC_PS_DESC_WRITES=$((QSC_PS_DESC_WRITES + 1))
		QSC_PS_DESC_FORCE=0
	else
		# 写入失败不能把失败的指纹缓存起来，否则同一电量/温度下
		# 后续轮次不会重试，module.prop 会永久停在旧值。
		QSC_PS_DESC_SIG=""
	fi
	# 写入后重新读取目标文件，区分「文件已更新但管理器缓存旧值」和
	# 「module.prop 实际没有写入/被覆盖」。
	_desc_file_match=0
	while IFS= read -r _desc_line || [ -n "$_desc_line" ]; do
		case "$_desc_line" in
			description=*"$lv"%*) _desc_file_match=1; break ;;
		esac
	done <"$MODDIR/module.prop"
	type qsc_runtime_trace >/dev/null 2>&1 &&
		qsc_runtime_trace "H7" "description_file" "$_desc_file_match:$lv"
	type qsc_runtime_trace >/dev/null 2>&1 &&
		qsc_runtime_trace "H4" "description_refresh" "$_desc_rc:$lv:$temp:$plugged:$stopped:v$viewer"
	return "$_desc_rc"
	# endregion
}

# 等待下一轮。native_daemon=1 且存在 bin/qscd 时交给它阻塞在内核
# power_supply uevent 上：插拔可立即返回，期间不产生定时唤醒；
# 开关关闭或缺少该二进制则退化为 sleep。
# 约定：qscd wait-event <最长秒> <最短秒> → 0=有事件或到时；非 0=不可用（此后改用 sleep）
# 最短秒是为了压掉充电时的 uevent 风暴，避免主循环被事件催成高频空转。
QSC_PS_WAIT_HELPER_OK=1
QSC_PS_WAIT_FLOOR=3

# 守护此刻是否真能用。
# 失败要落一个标记文件：qsc_switch.sh 是另一个进程，看不到主循环里的
# QSC_PS_WAIT_HELPER_OK，否则它会照着「有守护」算出放大后的间隔，
# 而主循环其实已经退回 sleep，插电就要等满那个大间隔才被发现。
# 标记在 service.sh 启动时清掉，换二进制后重新判定。
