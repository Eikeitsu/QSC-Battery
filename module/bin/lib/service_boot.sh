#!/system/bin/sh
# service: boot / workers / helpers
# （由 service.sh 在 common.sh 之后 source）

if [ -f "$LIBDIR/hot_update.sh" ]; then
	# shellcheck disable=SC1090
	. "$LIBDIR/hot_update.sh" 2>/dev/null || true
	if type hot_update_migrate_legacy_paths >/dev/null 2>&1 &&
		! hot_update_migrate_legacy_paths; then
		touch "$MODDIR/data/hot_update_fallback_reboot" "$MODDIR/update" 2>/dev/null
		qsc_write_module_description "⚠️热更新未完成" "请重启设备完成更新" \
			"外部恢复目录迁移失败，已保留旧副本"
	fi
fi

mkdir -p "$DATADIR"
QSC_SERVICE_BOOT_AT="$(date +%s 2>/dev/null)"
case "$QSC_SERVICE_BOOT_AT" in ""|*[!0-9]*) QSC_SERVICE_BOOT_AT=0 ;; esac
printf '%s\n' "$$" >"$DATADIR/service_pid" 2>/dev/null
printf 'pid=%s\nstarted_at=%s\nstate=starting\n' "$$" "$QSC_SERVICE_BOOT_AT" \
	>"$DATADIR/service_start.state.tmp" 2>/dev/null &&
	mv -f "$DATADIR/service_start.state.tmp" "$DATADIR/service_start.state" 2>/dev/null
printf '%s\n' "$QSC_SERVICE_BOOT_AT" >"$DATADIR/service_start_at" 2>/dev/null
QSC_HEARTBEAT_PID=0
qsc_service_exit() {
	[ "$QSC_HEARTBEAT_PID" -gt 0 ] 2>/dev/null &&
		kill "$QSC_HEARTBEAT_PID" 2>/dev/null || true
	if [ "$(cat "$DATADIR/service_pid" 2>/dev/null | tr -d ' \r\n')" = "$$" ]; then
		printf 'pid=%s\nstarted_at=%s\nstate=stopped\n' "$$" "$QSC_SERVICE_BOOT_AT" \
			>"$DATADIR/service_start.state.tmp" 2>/dev/null &&
			mv -f "$DATADIR/service_start.state.tmp" "$DATADIR/service_start.state" 2>/dev/null
		rm -f "$DATADIR/service_pid" 2>/dev/null
		rm -f "$DATADIR/service_heartbeat_pid" 2>/dev/null
	fi
}
trap qsc_service_exit 0 1 2 3 15

qsc_start_heartbeat_loop() {
	local parent="$1" file="$2" hb_sec
	# 心跳只给热更新/简介 worker 探活；写盘间隔不必到秒级。
	# 过密会在待机时持续拉起 shell（原先 5s）。间隔可读 power.conf。
	hb_sec=180
	if [ -f "${POWER_CONF:-}" ]; then
		_h="$(sed -n 's/^heartbeat_sec=//p' "$POWER_CONF" 2>/dev/null | head -n1 | tr -d ' \r\n')"
		case "$_h" in ""|*[!0-9]*) ;; *) hb_sec="$_h" ;; esac
	fi
	case "$hb_sec" in ""|*[!0-9]*) hb_sec=180 ;; esac
	[ "$hb_sec" -lt 60 ] 2>/dev/null && hb_sec=60
	[ "$hb_sec" -gt 900 ] 2>/dev/null && hb_sec=900
	_hb_loop='
		parent="$1"
		file="$2"
		hb_sec="$3"
		while kill -0 "$parent" 2>/dev/null; do
			now="$(date +%s 2>/dev/null)"
			case "$now" in ""|*[!0-9]*) now=0 ;; esac
			printf "%s\n" "$now" >"$file" 2>/dev/null
			# 运行中若 power.conf 改了心跳，下一轮生效
			if [ -f "'"${POWER_CONF:-}"'" ]; then
				n="$(sed -n "s/^heartbeat_sec=//p" "'"${POWER_CONF:-}"'" 2>/dev/null | head -n1 | tr -d " \\r\\n")"
				case "$n" in ""|*[!0-9]*) ;; *) hb_sec="$n" ;; esac
			fi
			case "$hb_sec" in ""|*[!0-9]*) hb_sec=180 ;; esac
			[ "$hb_sec" -lt 60 ] 2>/dev/null && hb_sec=60
			[ "$hb_sec" -gt 900 ] 2>/dev/null && hb_sec=900
			sleep "$hb_sec"
		done
	'
	if command -v setsid >/dev/null 2>&1; then
		setsid sh -c "$_hb_loop" sh "$parent" "$file" "$hb_sec" \
			</dev/null >/dev/null 2>&1 &
	else
		nohup sh -c "$_hb_loop" sh "$parent" "$file" "$hb_sec" \
			</dev/null >/dev/null 2>&1 &
	fi
	QSC_HEARTBEAT_PID=$!
	printf '%s\n' "$QSC_HEARTBEAT_PID" >"$DATADIR/service_heartbeat_pid" 2>/dev/null
}
qsc_start_heartbeat_loop "$$" "$DATADIR/service_heartbeat"

# 新版 worker 会在启动服务前释放锁；这里仅清理无内容的历史残留锁目录。
rmdir /data/adb/qsc/hot_update/lock 2>/dev/null

until [ -f "$BINDIR/qsc_switch.sh" ]; do
	qsc_log_once no_core error "核心脚本 qsc_switch.sh 丢失，请重新安装模块"
	qsc_write_module_description "⚠️异常" "核心脚本丢失" "请重新安装模块并重启"
	sleep 5
done

sleep 5
mkdir -p "$DATADIR" "$CONFDIR" "$ASSETDIR"

# 脚本权限由打包/安装阶段保证；不要在常驻服务启动时批量 chmod 整个 bin，
# 某些 Android 文件系统会让这类 glob 操作长时间阻塞，导致服务永远起不来。
# 配置和 WebUI 静态文件同样由打包/安装阶段设置权限。

sleep 1

echo "rm -f \"$MODULE_OFF_FLAG\"; echo 已打开充电控制" > "$MODDIR/打开充电控制.sh"
echo "touch \"$MODULE_OFF_FLAG\"; echo 已关闭充电控制" > "$MODDIR/关闭充电控制.sh"
chmod 0755 "$MODDIR/打开充电控制.sh"
chmod 0755 "$MODDIR/关闭充电控制.sh"
rm -f "$MODDIR/打开定量停充.sh" "$MODDIR/关闭定量停充.sh" 2>/dev/null

if [ -f "$ASSETDIR/pay.jpg" ] && [ ! -f "$ASSETDIR/donate.jpg" ]; then
	cp "$ASSETDIR/pay.jpg" "$ASSETDIR/donate.jpg"
fi

echo "# 给原作者 top大佬 投币（微信网页收款）" > "$MODDIR/给原作者top大佬投币.sh"
echo "am start -n com.tencent.mm/.plugin.webview.ui.tools.WebViewUI -d https://payapp.weixin.qq.com/qrpay/order/home2?key=idc_CHNDVI_dHFNbTNZIWMMKIEdzUZtCA-- >/dev/null 2>&1" >> "$MODDIR/给原作者top大佬投币.sh"
echo "echo \"\"" >> "$MODDIR/给原作者top大佬投币.sh"
echo "echo \"正在跳转原作者 top大佬 的投币页面，请稍等…\"" >> "$MODDIR/给原作者top大佬投币.sh"
chmod 0755 "$MODDIR/给原作者top大佬投币.sh"
# 清理旧文件名，避免与维护者打赏混淆
rm -f "$MODDIR/.投币捐赠.sh" "$MODDIR/投币捐赠.sh"

if [ -f "$MODDIR/t_module" -a "$(cat "$MODDIR/module.prop" | egrep '^# ##' | sed -n '$p')" != '# ##' ]; then
	cp "$MODDIR/t_module" "$MODDIR/module.prop"
	chmod 0644 "$MODDIR/module.prop"
fi

QSC_SCAN_LOCK="$DATADIR/.list_switch_scan.lock"
QSC_SCAN_STATE="$DATADIR/list_switch.state"

# 全量 /sys 扫描必须是一次性后台任务：主服务先用内置兜底节点进入循环，
# 扫描结束后再通过状态文件报告 ready/failed。锁目录带 pid，既防止每轮重复
# 拉起扫描，也能回收上一次被杀掉的陈旧锁。
qsc_start_switch_scan() {
	[ -s "$LIST_SWITCH" ] && {
		printf '%s\n' "ready" >"$QSC_SCAN_STATE" 2>/dev/null
		return 0
	}
	: >"$LIST_SWITCH"
	if [ -d "$QSC_SCAN_LOCK" ]; then
		_scan_pid="$(cat "$QSC_SCAN_LOCK/pid" 2>/dev/null | tr -d ' \r\n')"
		case "$_scan_pid" in
			""|*[!0-9]*) rm -rf "$QSC_SCAN_LOCK" 2>/dev/null ;;
			*) kill -0 "$_scan_pid" 2>/dev/null || rm -rf "$QSC_SCAN_LOCK" 2>/dev/null ;;
		esac
	fi
	mkdir "$QSC_SCAN_LOCK" 2>/dev/null || return 0
	printf '%s\n' "$$" >"$QSC_SCAN_LOCK/owner" 2>/dev/null
	_scan_job='
		scan="$1"
		state="$2"
		lock="$3"
		list="$4"
		printf "%s\n" "running" >"${state}.tmp.$$" 2>/dev/null &&
			mv -f "${state}.tmp.$$" "$state" 2>/dev/null
		sh "$scan" >/dev/null 2>&1
		rc=$?
		if [ "$rc" -eq 0 ] && [ -s "$list" ]; then
			printf "%s\n" "ready" >"${state}.tmp.$$" 2>/dev/null &&
				mv -f "${state}.tmp.$$" "$state" 2>/dev/null
		else
			printf "%s\n" "failed:$rc" >"${state}.tmp.$$" 2>/dev/null &&
				mv -f "${state}.tmp.$$" "$state" 2>/dev/null
		fi
		rm -rf "$lock" 2>/dev/null
	'
	if command -v setsid >/dev/null 2>&1; then
		setsid sh -c "$_scan_job" sh "$BINDIR/list_switch.sh" \
			"$QSC_SCAN_STATE" "$QSC_SCAN_LOCK" "$LIST_SWITCH" \
			</dev/null >/dev/null 2>&1 &
	else
		nohup sh -c "$_scan_job" sh "$BINDIR/list_switch.sh" \
			"$QSC_SCAN_STATE" "$QSC_SCAN_LOCK" "$LIST_SWITCH" \
			</dev/null >/dev/null 2>&1 &
	fi
	_scan_pid=$!
	printf '%s\n' "$_scan_pid" >"$QSC_SCAN_LOCK/pid" 2>/dev/null
}

qsc_start_switch_scan
# 插电后电流节点探测（未在充则跳过，主循环会重试）
if [ -f "$BINDIR/list_current.sh" ]; then
	chmod 0755 "$BINDIR/list_current.sh" 2>/dev/null
	"$BINDIR/list_current.sh" > /dev/null 2>&1 || true
fi
# 按本机节点生成/刷新 device.profile（MCA 等能力动态启用）
if [ -f "$BINDIR/detect_device.sh" ]; then
	"$BINDIR/detect_device.sh" > /dev/null 2>&1
else
	qsc_detect_and_write_profile > /dev/null 2>&1 || true
	qsc_log warn "缺少 detect_device.sh，使用内置机型探测"
fi
rm -f "$DATADIR/now_c"
rm -f "$DATADIR/history_last_lv"
# 启动清理：临时/调试类文件可清；充放电历史与事件线保留。
# debug.log 跨服务重启保留链路，仅做字节封顶（见 qsc_boot_cleanup_logs）。
if type qsc_boot_cleanup_logs >/dev/null 2>&1; then
	qsc_boot_cleanup_logs
else
	rm -f "$DATADIR/startup.log" "$DATADIR/service_diag"
	rm -f "$DATADIR"/qscd_wait_error.* "$DATADIR/qscd_unusable.tmp"
fi
rm -f "$DATADIR/off_d"
rm -f "$DATADIR/power_on"
# 残留停充节点每个开机周期查一次，由 qsc_switch.sh 首轮执行
rm -f "$DATADIR/.orphan_checked"
# 拔线防抖计数重新开始，避免拿着重启前的旧计数直接还原
rm -f "$DATADIR/unplug_streak"
# 守护可用性每次启动重新判定（可能换了二进制或换了机型）
rm -f "$DATADIR/qscd_unusable" "$DATADIR/qscd_features" \
	"$DATADIR/qscd_last_wake_reason"
rm -f /data/system/qsc_xp_arm 2>/dev/null || true
rm -f "$DATADIR/power_off"
# 每启动周期重试 MCA（避免上次误判永久跳过；真无效会再次标记）
rm -f "$DATADIR/mca_ineffective"
echo "$(date +%F_%T) service.sh 启动，开始循环" > "$DATADIR/service_start.log"
# XP 日志落点与镜像（供 APP/WebUI LSP 页）
type qsc_xp_bootstrap_logs >/dev/null 2>&1 && qsc_xp_bootstrap_logs
QSC_SERVICE_HEARTBEAT_LAST=0
QSC_SERVICE_LOOP_COUNT=0
QSC_SERVICE_FULL_ROUNDS=0
QSC_SERVICE_SKIP_ROUNDS=0
QSC_SERVICE_DIAG_LAST=0
# 清掉上一进程残留，避免热更新 verifier 读到旧 loop_count 误判已接管
printf '0\n' >"$DATADIR/service_loop_count" 2>/dev/null
printf '%s\n' "$QSC_SERVICE_BOOT_AT" >"$DATADIR/service_heartbeat" 2>/dev/null

QSC_HOT_TXN_STATE="/data/adb/qsc/hot_update/transactions/QSC_Battery/state"
if [ -f "$QSC_HOT_TXN_STATE" ] && [ ! -f "$DATADIR/hot_update_at" ]; then
	_hot_state="$(sed -n 's/^state=//p' "$QSC_HOT_TXN_STATE" 2>/dev/null | head -n1 | tr -d ' \r')"
	case "$_hot_state" in
		prepare|apply)
			sed -i 's/^state=.*/state=fallback/' "$QSC_HOT_TXN_STATE" 2>/dev/null || true
			touch "$DATADIR/hot_update_fallback_reboot" 2>/dev/null
			;;
	esac
fi
# region agent log
qsc_runtime_trace() {
	local hypothesis="$1" message="$2" value="$3" now="${QSC_PS_NOW:-0}"
	local note level category
	# 默认关：需 debug_on 或 diagnostic_on，避免待机写盘
	if ! qsc_debug_enabled; then
		[ -f "$DATADIR/diagnostic_on" ] || return 0
	fi
	case "$now" in ""|*[!0-9]*) now=0 ;; esac
	case "$message" in
		service_start)
			note="服务启动"; level=info; category=service
			;;
		description_worker_start)
			note="简介刷新 worker 启动"; level=info; category=worker
			;;
		description_worker_tick)
			note="简介刷新 worker 心跳"; level=trace; category=worker
			;;
		description_worker_refresh)
			note="简介刷新 worker 执行结果"; level=debug; category=worker
			;;
		description_worker_exit)
			note="简介刷新 worker 退出"; level=warn; category=worker
			;;
		loop_enter)
			note="主循环开始"; level=trace; category=service
			;;
		loop_lean)
			note="未插电 lean 再入"; level=trace; category=service
			;;
		after_description)
			note="简介刷新完成，准备判断后续流程"; level=trace; category=description
			;;
		flush_check)
			note="检查是否需要落盘历史数据"; level=trace; category=history
			;;
		flush_enter)
			note="开始落盘待处理历史数据"; level=debug; category=history
			;;
		flush_exit)
			note="历史数据落盘结束"; level=debug; category=history
			;;
		skip_result)
			note="判断本轮是否可以跳过完整决策"; level=debug; category=decision
			;;
		switch_enter)
			note="开始执行停充决策脚本"; level=debug; category=decision
			;;
		switch_exit)
			note="停充决策脚本执行结束"; level=debug; category=decision
			;;
		post_switch_description)
			note="停充决策后再次刷新简介"; level=debug; category=description
			;;
		wait_enter)
			note="开始等待下一轮"
			level="trace"
			category="wait"
			;;
		wait_exit)
			note="等待下一轮结束"
			level="trace"
			category="wait"
			;;
		snapshot)
			note="读取电池快照"; level=debug; category=snapshot
			;;
		description_file)
			note="校验 module.prop 是否包含当前电量"; level=debug; category=description
			;;
		description_refresh)
			note="简介刷新函数返回"; level=debug; category=description
			;;
		native_launcher)
			note="启动 qscd 等待器"; level=debug; category=qscd
			;;
		native_wait_enter)
			note="进入 qscd 等待"; level=trace; category=qscd
			;;
		native_wait_exit)
			note="qscd 等待结束"; level=debug; category=qscd
			;;
		native_wait_reason)
			note="qscd 等待结果及错误原因"; level=warn; category=qscd
			;;
		native_failure_enter)
			note="qscd 失败，进入回退流程"; level=warn; category=fallback
			;;
		failure_marker_exit)
			note="写入 qscd 失败标记结束"; level=debug; category=fallback
			;;
		failure_log_exit)
			note="记录 qscd 失败日志结束"; level=debug; category=fallback
			;;
		failure_wake_exit)
			note="记录回退唤醒原因结束"; level=debug; category=fallback
			;;
		fallback_sleep_enter)
			note="开始定时轮询回退等待"; level=info; category=fallback
			;;
		fallback_sleep_exit)
			note="定时轮询回退等待结束"; level=info; category=fallback
			;;
		*)
			note="未分类调试事件"; level=debug; category=unknown
			;;
	esac
	printf '{"level":"%s","category":"%s","hypothesisId":"%s","location":"service.sh","message":"%s","note":"%s","data":{"value":"%s","pid":"%s"},"timestamp":%s,"wall":"%s"}\n' \
		"$level" "$category" "$hypothesis" "$message" "$note" "$value" "$$" "$now" \
		"$(date +%F_%T 2>/dev/null)" >>"$DATADIR/debug.log" 2>/dev/null
	type qsc_trim_file_bytes >/dev/null 2>&1 &&
		qsc_trim_file_bytes "$DATADIR/debug.log" 262144 131072
}
# endregion
qsc_runtime_trace "H0" "service_start" "$$"

# 读当前电量（0–100）；失败返回空
qsc_ps_stat_read_cap() {
	local p v
	for p in "$PSDIR/battery/capacity" "$PSDIR/bms/capacity" "$PSDIR/battery/soc"; do
		[ -r "$p" ] || continue
		IFS= read -r v <"$p" 2>/dev/null || true
		v="$(printf '%s' "$v" | tr -d ' \r\n')"
		case "$v" in
			""|*[!0-9]*) ;;
			*)
				[ "$v" -le 100 ] 2>/dev/null && {
					printf '%s' "$v"
					return 0
				}
				;;
		esac
	done
	printf ''
}

# 读放电电流绝对值 mA；失败返回空
qsc_ps_stat_read_ma() {
	local ua abs
	[ -r "$PSDIR/battery/current_now" ] || {
		printf ''
		return 0
	}
	IFS= read -r ua <"$PSDIR/battery/current_now" 2>/dev/null || true
	ua="$(printf '%s' "$ua" | tr -d ' \r\n')"
	case "$ua" in
		""|*[!0-9-]*)
			printf ''
			return 0
			;;
	esac
	abs="${ua#-}"
	case "$abs" in
		""|*[!0-9]*)
			printf ''
			return 0
			;;
	esac
	printf '%s' "$((abs / 1000))"
}

# diagnostic_on：按心跳写出 service_power_stats + 一条 INFO（证明省电路径是否在工作）
qsc_ps_power_stats_flush() {
	local now="$1"
	local elapsed avg_sleep cap_now cap_delta pct_h ma ma_avg wl=0 plugged=0
	local loops skips full wakes sleep_sum sleep_n desc_w desc_sk viewers
	local wait_mode mins msg _pct10 _whole _frac

	[ -f "$DATADIR/diagnostic_on" ] || return 0
	case "$now" in ""|*[!0-9]*) return 0 ;; esac

	if [ "${QSC_PS_STAT_PERIOD_START:-0}" -eq 0 ] 2>/dev/null; then
		QSC_PS_STAT_PERIOD_START="$now"
	fi
	elapsed=$((now - QSC_PS_STAT_PERIOD_START))
	[ "$elapsed" -lt 1 ] 2>/dev/null && elapsed=1

	loops="${QSC_SERVICE_LOOP_COUNT:-0}"
	skips="${QSC_SERVICE_SKIP_ROUNDS:-0}"
	full="${QSC_SERVICE_FULL_ROUNDS:-0}"
	wakes="${QSC_PS_WAKE_COUNT:-0}"
	sleep_sum="${QSC_PS_SLEEP_SEC_SUM:-0}"
	sleep_n="${QSC_PS_SLEEP_COUNT:-0}"
	desc_w="${QSC_PS_DESC_WRITES:-0}"
	desc_sk="${QSC_PS_DESC_IDLE_SKIPS:-0}"
	viewers="${QSC_PS_VIEWER_HITS:-0}"
	wait_mode="${QSC_PS_NATIVE_MODE:-sleep}"
	[ -z "$wait_mode" ] && wait_mode="sleep"

	avg_sleep=0
	[ "$sleep_n" -gt 0 ] 2>/dev/null && avg_sleep=$((sleep_sum / sleep_n))

	if type qsc_ps_plugged >/dev/null 2>&1 && qsc_ps_plugged; then
		plugged=1
	fi
	[ -f "$DATADIR/wakelock_held" ] && wl=1

	cap_now="$(qsc_ps_stat_read_cap)"
	ma="$(qsc_ps_stat_read_ma)"
	cap_delta=""
	pct_h=""
	ma_avg=""
	if [ "$plugged" = "1" ]; then
		QSC_PS_STAT_CAP_START=""
		QSC_PS_STAT_MA_SUM=0
		QSC_PS_STAT_MA_N=0
	else
		case "$cap_now" in
			""|*[!0-9]*) ;;
			*)
				case "${QSC_PS_STAT_CAP_START:-}" in
					""|*[!0-9]*) QSC_PS_STAT_CAP_START="$cap_now" ;;
				esac
				;;
		esac
		case "${QSC_PS_STAT_CAP_START:-}" in
			""|*[!0-9]*) ;;
			*)
				case "$cap_now" in
					""|*[!0-9]*) ;;
					*)
						cap_delta=$((QSC_PS_STAT_CAP_START - cap_now))
						# 一位小数 %/h（掉电为正）
						_pct10=$((cap_delta * 36000 / elapsed))
						_whole=$((_pct10 / 10))
						_frac=$((_pct10 % 10))
						[ "$_frac" -lt 0 ] 2>/dev/null && _frac=$((0 - _frac))
						pct_h="${_whole}.${_frac}"
						;;
				esac
				;;
		esac
		case "$ma" in
			""|*[!0-9]*) ;;
			*)
				QSC_PS_STAT_MA_SUM=$((${QSC_PS_STAT_MA_SUM:-0} + ma))
				QSC_PS_STAT_MA_N=$((${QSC_PS_STAT_MA_N:-0} + 1))
				;;
		esac
		[ "${QSC_PS_STAT_MA_N:-0}" -gt 0 ] 2>/dev/null &&
			ma_avg=$((QSC_PS_STAT_MA_SUM / QSC_PS_STAT_MA_N))
	fi

	{
		printf 'period_start=%s\nperiod_end=%s\nelapsed_sec=%s\n' \
			"$QSC_PS_STAT_PERIOD_START" "$now" "$elapsed"
		printf 'loops=%s\nfull_rounds=%s\nskip_rounds=%s\n' \
			"$loops" "$full" "$skips"
		printf 'native_wakes=%s\nlast_wake=%s\nwait_mode=%s\n' \
			"$wakes" "${QSC_PS_LAST_WAKE_REASON:-}" "$wait_mode"
		printf 'sleep_sec_sum=%s\nsleep_count=%s\navg_sleep_sec=%s\n' \
			"$sleep_sum" "$sleep_n" "$avg_sleep"
		printf 'desc_writes=%s\ndesc_idle_skips=%s\nviewer_hits=%s\n' \
			"$desc_w" "$desc_sk" "$viewers"
		printf 'wakelock_held=%s\nplugged=%s\n' "$wl" "$plugged"
		printf 'cap_start=%s\ncap_now=%s\ncap_delta=%s\npct_per_hour=%s\n' \
			"${QSC_PS_STAT_CAP_START:-}" "${cap_now:-}" "${cap_delta:-}" "${pct_h:-}"
		printf 'ma_avg=%s\nma_now=%s\n' "${ma_avg:-}" "${ma:-}"
	} >"$DATADIR/service_power_stats.tmp" 2>/dev/null &&
		mv -f "$DATADIR/service_power_stats.tmp" "$DATADIR/service_power_stats" 2>/dev/null

	mins=$((elapsed / 60))
	[ "$mins" -lt 1 ] 2>/dev/null && mins=1
	msg="省电统计 ${mins}m：skip ${skips}/${loops} 满轮${full} 均睡${avg_sleep}s 简介写${desc_w}/跳过${desc_sk}"
	case "$cap_now" in
		""|*[!0-9]*) ;;
		*)
			msg="${msg} 电量${QSC_PS_STAT_CAP_START:-?}→${cap_now}"
			[ -n "$pct_h" ] && msg="${msg} ≈${pct_h}%/h"
			;;
	esac
	[ -n "$ma_avg" ] && msg="${msg} ≈${ma_avg}mA"
	msg="${msg} wake=${QSC_PS_LAST_WAKE_REASON:-?} mode=${wait_mode} wl=${wl}"
	qsc_log info "$msg"
}

qsc_service_heartbeat() {
	local now pending hb_gap
	now="${QSC_PS_NOW:-$(date +%s 2>/dev/null)}"
	case "$now" in ""|*[!0-9]*) return 0 ;; esac
	# loop_count 每轮都写：热更新 verifier 要尽快看到 loops>0，不能等心跳门闩
	printf '%s\n' "$QSC_SERVICE_LOOP_COUNT" >"$DATADIR/service_loop_count" 2>/dev/null
	hb_gap="${QSC_PS_HB_SEC:-180}"
	case "$hb_gap" in ""|*[!0-9]*) hb_gap=180 ;; esac
	[ "$hb_gap" -lt 60 ] 2>/dev/null && hb_gap=60
	if [ "$QSC_SERVICE_HEARTBEAT_LAST" -eq 0 ] ||
		[ "$((now - QSC_SERVICE_HEARTBEAT_LAST))" -ge "$hb_gap" ] 2>/dev/null; then
		printf '%s\n' "$now" >"$DATADIR/service_heartbeat" 2>/dev/null
		printf 'timestamp=%s\nloops=%s\nfull_rounds=%s\nnative_wakes=%s\nwake_reason=%s\n' \
			"$now" "$QSC_SERVICE_LOOP_COUNT" "$QSC_SERVICE_FULL_ROUNDS" \
			"${QSC_PS_WAKE_COUNT:-0}" "${QSC_PS_LAST_WAKE_REASON:-}" \
			>"$DATADIR/service_metrics.tmp" 2>/dev/null &&
			mv -f "$DATADIR/service_metrics.tmp" "$DATADIR/service_metrics" 2>/dev/null
		printf 'pid=%s\nstarted_at=%s\nstate=running\nmode=%s\n' \
			"$$" "$QSC_SERVICE_BOOT_AT" "${QSC_PS_MODE:-}" \
			>"$DATADIR/service_start.state.tmp" 2>/dev/null &&
			mv -f "$DATADIR/service_start.state.tmp" "$DATADIR/service_start.state" 2>/dev/null
		if qsc_debug_enabled; then
			printf '%s\n' "${QSC_PS_LAST_WAKE_REASON:-}" \
				>"$DATADIR/qscd_last_wake_reason" 2>/dev/null
		fi
		# 省电证据：仅 diagnostic_on，跟心跳同频，避免密写盘
		type qsc_ps_power_stats_flush >/dev/null 2>&1 &&
			qsc_ps_power_stats_flush "$now"
		QSC_SERVICE_HEARTBEAT_LAST="$now"
	fi
	# 诊断采样默认关闭；touch data/diagnostic_on 后每 10 秒记录一次详细
	# 计数，便于真机测量唤醒/写盘，不把额外写盘成本带给普通用户。
	if [ -f "$DATADIR/diagnostic_on" ] &&
		{ [ "$QSC_SERVICE_DIAG_LAST" -eq 0 ] ||
			[ "$((now - QSC_SERVICE_DIAG_LAST))" -ge 10 ] 2>/dev/null; }; then
		pending=0
		if [ -f "${QSC_HISTORY_BUFFER:-$DATADIR/charge_history.csv.pending}" ]; then
			pending="$(wc -l <"${QSC_HISTORY_BUFFER:-$DATADIR/charge_history.csv.pending}" 2>/dev/null | tr -d ' ')"
		fi
		case "$pending" in ""|*[!0-9]*) pending=0 ;; esac
		printf 'timestamp=%s\nloops=%s\nfull_rounds=%s\nskip_rounds=%s\nnative_wakes=%s\n' \
			"$now" "$QSC_SERVICE_LOOP_COUNT" "$QSC_SERVICE_FULL_ROUNDS" \
			"${QSC_SERVICE_SKIP_ROUNDS:-0}" "${QSC_PS_WAKE_COUNT:-0}" \
			>"$DATADIR/service_diag.tmp" 2>/dev/null
		printf 'description_writes=%s\ndesc_idle_skips=%s\nsleep_sec_sum=%s\nhistory_pending=%s\nnative_failure=%s\n' \
			"${QSC_PS_DESC_WRITES:-0}" "${QSC_PS_DESC_IDLE_SKIPS:-0}" \
			"${QSC_PS_SLEEP_SEC_SUM:-0}" "$pending" \
			"${QSC_PS_NATIVE_ERROR:-}" >>"$DATADIR/service_diag.tmp" 2>/dev/null &&
			mv -f "$DATADIR/service_diag.tmp" "$DATADIR/service_diag" 2>/dev/null
		QSC_SERVICE_DIAG_LAST="$now"
	fi
}
if [ -f "$DATADIR/hot_update_fallback_reboot" ]; then
	qsc_write_module_description "⚠️热更新未完成" "请重启设备完成更新" \
		"服务接管未确认，已保留标准更新流程"
elif [ -f "$DATADIR/hot_update_at" ]; then
	if qsc_description_enabled 2>/dev/null; then
		qsc_write_module_description "♻️更新中" "服务已重启" \
			"本次更新无需重启；正在读取实时充电状态"
	fi
	# 补发 viewer enter，避免热更新空窗里 XP 边沿过期导致简介永不勤刷
	_hu_now="$(date +%s 2>/dev/null || echo 0)"
	if type qsc_xp_write_bus >/dev/null 2>&1; then
		qsc_xp_write_bus /data/system/qsc_xp_viewer \
			"$(printf '%s\tenter\thot_update\n' "$_hu_now")"
	else
		printf '%s\tenter\thot_update\n' "$_hu_now" \
			>/data/system/qsc_xp_viewer 2>/dev/null || true
		chmod 0666 /data/system/qsc_xp_viewer 2>/dev/null || true
	fi
	rm -f "$DATADIR/hot_update_at"
	# 不要等设备探测、兼容模块扫描和全量节点扫描完成后才刷新简介。
	# 这些任务可能较慢，先用当前电量/温度/供电状态覆盖临时的「更新中」。
	if type qsc_ps_load_conf >/dev/null 2>&1; then
		QSC_PS_DESC_FORCE=1
		qsc_ps_load_conf
		qsc_ps_now
		qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
		QSC_PS_DESC_FORCE=0
	fi
elif qsc_description_enabled 2>/dev/null; then
	qsc_write_module_description "🔎启动中" "服务已拉起" "$DESC_INTRO"
else
	type qsc_description_restore_static >/dev/null 2>&1 &&
		qsc_description_restore_static
fi

# 简介刷新 worker 要在所有可能阻塞的初始化任务之前启动。
# 否则 list_curr/detect_device 或兼容模块扫描只要卡住，热更新后的过渡文案
# 就会先成功变成一轮电量，随后没有任何进程继续刷新。
qsc_stop_description_worker() {
	local pid_file="$DATADIR/description_worker.pid" pid i
	pid="$(cat "$pid_file" 2>/dev/null | tr -d ' \r\n')"
	case "$pid" in
		""|*[!0-9]*) ;;
		*)
			kill "$pid" 2>/dev/null || true
			i=0
			while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 5 ]; do
				sleep 1
				i=$((i + 1))
			done
			kill -9 "$pid" 2>/dev/null || true
			;;
	esac
	rm -f "$pid_file" 2>/dev/null
	rm -rf "$DATADIR/.description_worker.lock" 2>/dev/null
}

qsc_start_description_worker() {
	# 用 sh 显式解释，不能把执行权限当成 worker 是否存在的判断条件。
	# 某些热更新器解压新文件时会暂时丢失 0755；这不应让简介刷新静默失效。
	[ -f "$BINDIR/description_worker.sh" ] || return 0
	if ! qsc_description_enabled 2>/dev/null; then
		qsc_stop_description_worker
		type qsc_description_restore_static >/dev/null 2>&1 &&
			qsc_description_restore_static
		return 0
	fi
	# 已在跑则复用
	_desc_pid="$(cat "$DATADIR/description_worker.pid" 2>/dev/null | tr -d ' \r\n')"
	case "$_desc_pid" in
		""|*[!0-9]*) ;;
		*)
			kill -0 "$_desc_pid" 2>/dev/null && return 0
			;;
	esac
	qsc_stop_description_worker
	if command -v setsid >/dev/null 2>&1; then
		setsid sh "$BINDIR/description_worker.sh" "$$" \
			</dev/null >/dev/null 2>&1 &
	else
		nohup sh "$BINDIR/description_worker.sh" "$$" \
			</dev/null >/dev/null 2>&1 &
	fi
	qsc_runtime_trace "H0" "description_worker_start" "$!"
}

# 按需：仅 enter 待消费 / 正在观看 / 无 XP 亮屏降级时启动
if type qsc_ps_policy_refresh >/dev/null 2>&1; then
	qsc_ps_now 2>/dev/null
	qsc_ps_policy_refresh 2>/dev/null || true
fi
if type qsc_ps_desc_worker_wanted >/dev/null 2>&1 &&
	qsc_ps_desc_worker_wanted; then
	qsc_start_description_worker
else
	qsc_stop_description_worker
fi

# 尽早把管理器包名表同步到 /data/system，供 LSPosed 前台边沿合并（含隐藏 Magisk）
if type qsc_manager_viewer_build_list >/dev/null 2>&1; then
	qsc_manager_viewer_build_list >/dev/null 2>&1 || true
fi
if type qsc_xp_sync_fg_policy >/dev/null 2>&1; then
	qsc_xp_sync_fg_policy >/dev/null 2>&1 || true
fi

# 探测 AccA 等限流模块（提示开兼容模式）
if type qsc_detect_compat_modules >/dev/null 2>&1; then
	qsc_detect_compat_modules >/dev/null 2>&1 || true
fi

# 默认循环间隔；qsc_switch 会按停充态改写 data/loop_sleep
echo 3 >"$DATADIR/loop_sleep" 2>/dev/null

QSC_PS_LAST_FULL=0

# 免重启更新的运行期兜底。第三方安装器（InstallX 等）会连带杀掉安装时
# 脱离出去的收尾作业，留下 modules_update 暂存与 update 标记，用户就看到
# 「还是要重启」。常驻服务活得比任何安装器都久，由它复查一遍最稳。
# 热路径只多一次 [ -f update ] 判断，命中才做后面那些事。
QSC_HOT_FIN_TS=0
QSC_HOT_FIN_TRIES=0

qsc_hot_finalize_maybe() {
	local now
	# 热更新事务由外部 worker 负责 verify/commit；服务不能在首轮运行时
	# 抢先清掉 update 和 payload，否则失败后就失去标准重启来源。
	[ -f "/data/adb/qsc/hot_update/transactions/QSC_Battery/state" ] &&
		return 0
	[ -f "$MODDIR/update" ] || \
		[ -d "/data/adb/qsc/hot_update/payload/QSC_Battery" ] || return 0
	type qsc_hot_finalize >/dev/null 2>&1 || return 0
	# 失败时别每轮重试：最多 5 次，每次至少隔 60 秒
	[ "$QSC_HOT_FIN_TRIES" -ge 5 ] 2>/dev/null && return 0
	now="$(date +%s 2>/dev/null)" || now=0
	case "$now" in "" | *[!0-9]*) now=0 ;; esac
	if [ "$now" -gt 0 ] && [ "$QSC_HOT_FIN_TS" -gt 0 ] \
		&& [ "$((now - QSC_HOT_FIN_TS))" -lt 60 ] 2>/dev/null; then
		return 0
	fi
	QSC_HOT_FIN_TS="$now"
	QSC_HOT_FIN_TRIES=$((QSC_HOT_FIN_TRIES + 1))
	qsc_hot_finalize || true
}

qsc_hot_finalize_maybe

# power_saver.sh 缺失（如手动裁剪安装）时退化为普通 sleep
if ! type qsc_ps_wait >/dev/null 2>&1; then
	qsc_ps_wait() { sleep "${1:-3}"; }
fi
type qsc_ps_log_startup >/dev/null 2>&1 && qsc_ps_log_startup
