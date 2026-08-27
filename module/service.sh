#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/bin/common.sh"

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
# 守护可用性每次启动重新判定（可能换了二进制或换了机型）
rm -f "$DATADIR/qscd_unusable" "$DATADIR/qscd_watch"
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

# power_saver.sh 缺失（如手动裁剪安装）时退化为普通 sleep
if ! type qsc_ps_wait >/dev/null 2>&1; then
	qsc_ps_wait() { sleep "${1:-3}"; }
fi

while true ; do
	# 省电快路径：未插电且未维持停充时，本轮只读几个 online 节点就睡，
	# 不 fork qsc_switch.sh（那会重新解析约 90KB 脚本并触发多次写盘）。
	if type qsc_ps_load_conf >/dev/null 2>&1; then
		qsc_ps_load_conf
		qsc_ps_now
		_now="$QSC_PS_NOW"
		if qsc_ps_can_skip_round "$_now"; then
			# 整轮跳过也要刷简介，否则管理器里的电量/温度会停在上一次满轮
			if type qsc_ps_refresh_desc >/dev/null 2>&1; then
				qsc_ps_refresh_desc "$_now"
			fi
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
