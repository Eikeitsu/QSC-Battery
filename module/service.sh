#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/bin/common.sh"

# 新版 worker 会在启动服务前释放锁；这里仅清理无内容的历史残留锁目录。
rmdir /data/adb/.QSC_Battery.hot_update.lock 2>/dev/null

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

echo "rm -f \"$OFF_FLAG\"; echo 已打开充电控制" > "$MODDIR/打开充电控制.sh"
echo "touch \"$OFF_FLAG\"; echo 已关闭充电控制" > "$MODDIR/关闭充电控制.sh"
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
if [ -f "$BINDIR/list_curr.sh" ]; then
	chmod 0755 "$BINDIR/list_curr.sh" 2>/dev/null
	"$BINDIR/list_curr.sh" > /dev/null 2>&1 || true
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
# 启动日志只保留本次服务入口；debug.log 要跨服务重启保留，才能追踪 PID
# 变化与服务中断前后的完整链路。
rm -f "$DATADIR/startup.log"
rm -f "$DATADIR/service_diag"
rm -f "$DATADIR/off_d"
rm -f "$DATADIR/power_on"
# 残留停充节点每个开机周期查一次，由 qsc_switch.sh 首轮执行
rm -f "$DATADIR/.orphan_checked"
# 拔线防抖计数重新开始，避免拿着重启前的旧计数直接还原
rm -f "$DATADIR/unplug_streak"
# 守护可用性每次启动重新判定（可能换了二进制或换了机型）
rm -f "$DATADIR/qscd_unusable" "$DATADIR/qscd_features" \
	"$DATADIR/qscd_last_wake_reason"
rm -f "$DATADIR"/qscd_wait_error.* "$DATADIR/qscd_unusable.tmp"
rm -f "$DATADIR/power_off"
echo "$(date +%F_%T) service.sh 启动，开始循环" > "$DATADIR/service_start.log"
QSC_SERVICE_HEARTBEAT_LAST=0
QSC_SERVICE_LOOP_COUNT=0
QSC_SERVICE_FULL_ROUNDS=0
QSC_SERVICE_DIAG_LAST=0
# region agent log
qsc_runtime_trace() {
	local hypothesis="$1" message="$2" value="$3" now="${QSC_PS_NOW:-0}"
	local note level category
	qsc_debug_enabled || return 0
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
}
# endregion
qsc_runtime_trace "H0" "service_start" "$$"
qsc_service_heartbeat() {
	local now pending
	now="${QSC_PS_NOW:-$(date +%s 2>/dev/null)}"
	case "$now" in ""|*[!0-9]*) return 0 ;; esac
	if [ "$QSC_SERVICE_HEARTBEAT_LAST" -eq 0 ] ||
		[ "$((now - QSC_SERVICE_HEARTBEAT_LAST))" -ge 60 ] 2>/dev/null; then
		printf '%s\n' "$now" >"$DATADIR/service_heartbeat" 2>/dev/null
		printf '%s\n' "$QSC_SERVICE_LOOP_COUNT" >"$DATADIR/service_loop_count" 2>/dev/null
		printf 'timestamp=%s\nloops=%s\nfull_rounds=%s\nnative_wakes=%s\nwake_reason=%s\n' \
			"$now" "$QSC_SERVICE_LOOP_COUNT" "$QSC_SERVICE_FULL_ROUNDS" \
			"${QSC_PS_WAKE_COUNT:-0}" "${QSC_PS_LAST_WAKE_REASON:-}" \
			>"$DATADIR/service_metrics.tmp" 2>/dev/null &&
			mv -f "$DATADIR/service_metrics.tmp" "$DATADIR/service_metrics" 2>/dev/null
		if qsc_debug_enabled; then
			printf '%s\n' "${QSC_PS_LAST_WAKE_REASON:-}" \
				>"$DATADIR/qscd_last_wake_reason" 2>/dev/null
		fi
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
		printf 'timestamp=%s\nloops=%s\nfull_rounds=%s\nnative_wakes=%s\n' \
			"$now" "$QSC_SERVICE_LOOP_COUNT" "$QSC_SERVICE_FULL_ROUNDS" \
			"${QSC_PS_WAKE_COUNT:-0}" \
			>"$DATADIR/service_diag.tmp" 2>/dev/null
		printf 'description_writes=%s\nhistory_pending=%s\nnative_failure=%s\n' \
			"${QSC_PS_DESC_WRITES:-0}" "$pending" \
			"${QSC_PS_NATIVE_ERROR:-}" >>"$DATADIR/service_diag.tmp" 2>/dev/null &&
			mv -f "$DATADIR/service_diag.tmp" "$DATADIR/service_diag" 2>/dev/null
		QSC_SERVICE_DIAG_LAST="$now"
	fi
}
if [ -f "$DATADIR/hot_update_at" ]; then
		qsc_write_module_description "♻️更新中" "服务已重启" \
			"本次更新无需重启；正在读取实时充电状态"
	rm -f "$DATADIR/hot_update_at"
	# 不要等设备探测、兼容模块扫描和全量节点扫描完成后才刷新简介。
	# 这些任务可能较慢，先用当前电量/温度/供电状态覆盖临时的「更新中」。
	if type qsc_ps_load_conf >/dev/null 2>&1; then
		qsc_ps_load_conf
		qsc_ps_now
		qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
	fi
else
	qsc_write_module_description "🔎启动中" "服务已拉起" "$DESC_INTRO"
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
if [ -f "$LIBDIR/hot_update.sh" ]; then
	# shellcheck disable=SC1090
	. "$LIBDIR/hot_update.sh" 2>/dev/null || true
fi
QSC_HOT_FIN_TS=0
QSC_HOT_FIN_TRIES=0

qsc_hot_finalize_maybe() {
	local now
	[ -f "$MODDIR/update" ] || \
		[ -d "/data/adb/.qsc_hot_update_payload/QSC_Battery" ] || return 0
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

# 简介刷新不应与 qscd 等待器绑定在同一条执行链上。主循环进入等待器、
# 决策脚本异常或被系统短暂重启时，独立 worker 仍能更新 module.prop；
# 父服务退出后 worker 会自动结束，避免留下常驻孤儿进程。
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
	[ -x "$BINDIR/description_worker.sh" ] || return 0
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

qsc_start_description_worker

# power_saver.sh 缺失（如手动裁剪安装）时退化为普通 sleep
if ! type qsc_ps_wait >/dev/null 2>&1; then
	qsc_ps_wait() { sleep "${1:-3}"; }
fi

while true ; do
	QSC_SERVICE_LOOP_COUNT=$((QSC_SERVICE_LOOP_COUNT + 1))
	qsc_hot_finalize_maybe
	# 省电快路径：未插电且未维持停充时，本轮只读几个 online 节点就睡，
	# 不 fork qsc_switch.sh（那会重新解析约 90KB 脚本并触发多次写盘）。
	if type qsc_ps_load_conf >/dev/null 2>&1; then
		qsc_ps_load_conf
		qsc_ps_now
		_now="$QSC_PS_NOW"
		# region agent log
		qsc_runtime_trace "H1" "loop_enter" "$QSC_SERVICE_LOOP_COUNT:$_now"
		# endregion
		qsc_service_heartbeat
		# 即使本轮准备跳过 qsc_switch，也要用当前供电状态刷新模块简介。
		if type qsc_ps_refresh_desc >/dev/null 2>&1; then
			qsc_ps_refresh_desc "$_now"
		fi
		# region agent log
		qsc_runtime_trace "H1" "after_description" "$QSC_SERVICE_LOOP_COUNT"
		# endregion
		# 拔电后立即落盘未满批次的充电采样，避免最近几条电流数据只留在
		# pending 文件里；仍在充电时不调用，保持批量写盘的省电收益。
		# region agent log
		qsc_runtime_trace "H5" "flush_check" "$QSC_SERVICE_LOOP_COUNT"
		# endregion
		if ! qsc_ps_plugged && type qsc_history_flush_pending >/dev/null 2>&1; then
			# region agent log
			qsc_runtime_trace "H5" "flush_enter" "$QSC_SERVICE_LOOP_COUNT"
			# endregion
			qsc_history_flush_pending
			# region agent log
			_flush_rc="$?"
			qsc_runtime_trace "H5" "flush_exit" "$_flush_rc"
			# endregion
		fi
		# region agent log
		qsc_ps_can_skip_round "$_now"
		_skip_rc="$?"
		qsc_runtime_trace "H1" "skip_result" "$_skip_rc"
		# endregion
		if [ "$_skip_rc" -eq 0 ]; then
			if type qsc_ps_idle_secs >/dev/null 2>&1; then
				qsc_ps_idle_secs
			else
				QSC_PS_IDLE_EFF="${QSC_PS_IDLE:-30}"
			fi
			qsc_ps_wait "$QSC_PS_IDLE_EFF"
			# region agent log
			_wait_rc="$?"
			qsc_runtime_trace "H1" "wait_exit" "$_wait_rc"
			# endregion
			continue
		fi
		[ "$_now" -gt 0 ] 2>/dev/null && QSC_PS_LAST_FULL="$_now"
		# 满轮会自己改简介，快路径的缓存指纹随之失效
		QSC_PS_DESC_SIG=""
	fi

	QSC_SERVICE_FULL_ROUNDS=$((QSC_SERVICE_FULL_ROUNDS + 1))
	# 停充决策属于可恢复的单轮任务，不能让某个 sysfs/系统服务调用把
	# 主循环永久占住；超时后下一轮会继续刷新简介和重新评估。
	# region agent log
	qsc_runtime_trace "H6" "switch_enter" "$QSC_SERVICE_FULL_ROUNDS"
	# endregion
	if type qsc_ps_native_exec >/dev/null 2>&1; then
		qsc_ps_native_exec 45 "$BINDIR/qsc_switch.sh" > /dev/null 2>&1
	else
		"$BINDIR/qsc_switch.sh" > /dev/null 2>&1
	fi
	# region agent log
	_switch_rc="$?"
	qsc_runtime_trace "H6" "switch_exit" "$_switch_rc"
	# endregion
	# qsc_switch 期间电量/供电状态可能已经变化；等待前再刷新一次，
	# 避免 module.prop 在下一次 qscd 唤醒前继续显示旧快照。
	if type qsc_ps_load_conf >/dev/null 2>&1 && type qsc_ps_refresh_desc >/dev/null 2>&1; then
		qsc_ps_load_conf
		qsc_ps_now
		qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"
		# region agent log
		qsc_runtime_trace "H8" "post_switch_description" "$?"
		# endregion
	fi
	_sleep="$(cat "$DATADIR/loop_sleep" 2>/dev/null | tr -d ' \r\n')"
	case "$_sleep" in
		""|*[!0-9]*) _sleep=3 ;;
	esac
	[ "$_sleep" -ge 2 ] 2>/dev/null || _sleep=3
	[ "$_sleep" -le 300 ] 2>/dev/null || _sleep=300
	QSC_PS_WAIT_FALLBACK="$_sleep"
	# region agent log
	qsc_runtime_trace "H1" "wait_enter" "$_sleep"
	# endregion
	qsc_ps_wait "$_sleep"
	# region agent log
	_wait_rc="$?"
	qsc_runtime_trace "H1" "wait_exit" "$_wait_rc"
	# endregion
done
