#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/bin/common.sh"

until [ -f "$BINDIR/qsc_switch.sh" ]; do
	sed -i 's/\[.*\]/\[ 文件 bin/qsc_switch.sh 丢失，请重新安装模块重启 \]/g' "$MODDIR/module.prop"
	sleep 5
done

sleep 5
mkdir -p "$DATADIR" "$CONFDIR" "$ASSETDIR"
[ ! -f "$CONF" ] && [ -f "$MODDIR/config.conf" ] && mv "$MODDIR/config.conf" "$CONF"

chmod 0755 "$BINDIR"/*.sh 2>/dev/null
chmod 0644 "$CONF" 2>/dev/null
[ -d "$MODDIR/webroot" ] && find "$MODDIR/webroot" -type f -exec chmod 0644 {} \;

sleep 1

echo "rm -f \"$OFF_FLAG\"" > "$MODDIR/打开定量停充.sh"
echo "touch \"$OFF_FLAG\"" > "$MODDIR/关闭定量停充.sh"
chmod 0755 "$MODDIR/打开定量停充.sh"
chmod 0755 "$MODDIR/关闭定量停充.sh"

if [ -f "$ASSETDIR/pay.jpg" ] && [ ! -f "$ASSETDIR/donate.jpg" ]; then
	cp "$ASSETDIR/pay.jpg" "$ASSETDIR/donate.jpg"
fi
[ -f "$MODDIR/pay.jpg" ] && [ ! -f "$ASSETDIR/pay.jpg" ] && mv "$MODDIR/pay.jpg" "$ASSETDIR/pay.jpg"

echo "#执行该脚本，跳转微信网页给作者投币捐赠" > "$MODDIR/.投币捐赠.sh"
echo "am start -n com.tencent.mm/.plugin.webview.ui.tools.WebViewUI -d https://payapp.weixin.qq.com/qrpay/order/home2?key=idc_CHNDVI_dHFNbTNZIWMMKIEdzUZtCA-- >/dev/null 2>&1" >> "$MODDIR/.投币捐赠.sh"
echo "echo \"\"" >> "$MODDIR/.投币捐赠.sh"
echo "echo \"正在跳转QSC定量停充捐赠页面，请稍等。。。\"" >> "$MODDIR/.投币捐赠.sh"
chmod 0755 "$MODDIR/.投币捐赠.sh"

if [ -f "$MODDIR/t_module" -a "$(cat "$MODDIR/module.prop" | egrep '^# ##' | sed -n '$p')" != '# ##' ]; then
	cp "$MODDIR/t_module" "$MODDIR/module.prop"
	chmod 0644 "$MODDIR/module.prop"
fi

rm -f "$LIST_SWITCH"
"$BINDIR/list_switch.sh" > /dev/null 2>&1
rm -f "$DATADIR/now_c"
rm -f "$DATADIR/off_d"
rm -f "$DATADIR/power_on"
rm -f "$DATADIR/power_off"
echo "$(date +%F_%T) service.sh 启动，开始循环" > "$DATADIR/service_start.log"
[ -f "$DATADIR/migrate.log" ] && tail -n 3 "$DATADIR/migrate.log" >> "$DATADIR/service_start.log"

while true ; do
	"$BINDIR/qsc_switch.sh" > /dev/null 2>&1
	sleep 3
done
