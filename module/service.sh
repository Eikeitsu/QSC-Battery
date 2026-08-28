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

chmod 0755 "$BINDIR"/*.sh 2>/dev/null
chmod 0644 "$CONF" 2>/dev/null
[ -d "$MODDIR/webroot" ] && find "$MODDIR/webroot" -type f -exec chmod 0644 {} \;

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

# 不预先删除 list_switch：由 list_switch.sh 写入临时文件，成功后再替换（失败保留旧列表）
"$BINDIR/list_switch.sh" > /dev/null 2>&1
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
# 旧版本每轮都写这两个文件，可能已积到很大；调试时会重新生成
rm -f "$DATADIR/startup.log" "$DATADIR/debug.log"
rm -f "$DATADIR/off_d"
rm -f "$DATADIR/power_on"
# 残留停充节点每个开机周期查一次，由 qsc_switch.sh 首轮执行
rm -f "$DATADIR/.orphan_checked"
# 拔线防抖计数重新开始，避免拿着重启前的旧计数直接还原
rm -f "$DATADIR/unplug_streak"
# 守护可用性每次启动重新判定（可能换了二进制或换了机型）
rm -f "$DATADIR/qscd_unusable" "$DATADIR/qscd_features" \
	"$DATADIR/qscd_last_wake_reason"
rm -f "$DATADIR/power_off"
echo "$(date +%F_%T) service.sh 启动，开始循环" > "$DATADIR/service_start.log"
if [ -f "$DATADIR/hot_update_at" ]; then
	qsc_write_module_description "♻️已热更新" "服务已重启" \
		"本次更新无需重启；实时状态将在下一轮刷新"
	rm -f "$DATADIR/hot_update_at"
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

# power_saver.sh 缺失（如手动裁剪安装）时退化为普通 sleep
if ! type qsc_ps_wait >/dev/null 2>&1; then
	qsc_ps_wait() { sleep "${1:-3}"; }
fi

while true ; do
	qsc_hot_finalize_maybe
	# 省电快路径：未插电且未维持停充时，本轮只读几个 online 节点就睡，
	# 不 fork qsc_switch.sh（那会重新解析约 90KB 脚本并触发多次写盘）。
	if type qsc_ps_load_conf >/dev/null 2>&1; then
		qsc_ps_load_conf
		qsc_ps_now
		_now="$QSC_PS_NOW"
		# 即使本轮准备跳过 qsc_switch，也要用当前供电状态刷新模块简介。
		if type qsc_ps_refresh_desc >/dev/null 2>&1; then
			qsc_ps_refresh_desc "$_now"
		fi
		if qsc_ps_can_skip_round "$_now"; then
			if type qsc_ps_idle_secs >/dev/null 2>&1; then
				qsc_ps_idle_secs
			else
				QSC_PS_IDLE_EFF="${QSC_PS_IDLE:-30}"
			fi
			qsc_ps_wait "$QSC_PS_IDLE_EFF"
			continue
		fi
		[ "$_now" -gt 0 ] 2>/dev/null && QSC_PS_LAST_FULL="$_now"
		# 满轮会自己改简介，快路径的缓存指纹随之失效
		QSC_PS_DESC_SIG=""
	fi

	"$BINDIR/qsc_switch.sh" > /dev/null 2>&1
	_sleep="$(cat "$DATADIR/loop_sleep" 2>/dev/null | tr -d ' \r\n')"
	case "$_sleep" in
		""|*[!0-9]*) _sleep=3 ;;
	esac
	[ "$_sleep" -ge 2 ] 2>/dev/null || _sleep=3
	[ "$_sleep" -le 300 ] 2>/dev/null || _sleep=300
	qsc_ps_wait "$_sleep"
done
