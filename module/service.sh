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
rm -f "$DATADIR/off_d"
rm -f "$DATADIR/power_on"
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

while true ; do
	"$BINDIR/qsc_switch.sh" > /dev/null 2>&1
	_sleep="$(cat "$DATADIR/loop_sleep" 2>/dev/null | tr -d ' \r\n')"
	case "$_sleep" in
		""|*[!0-9]*) _sleep=3 ;;
	esac
	[ "$_sleep" -ge 2 ] 2>/dev/null || _sleep=3
	[ "$_sleep" -le 60 ] 2>/dev/null || _sleep=60
	sleep "$_sleep"
done
