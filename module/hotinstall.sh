#!/system/bin/sh
# 热更新后立即拉起服务
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
MODDIR="${0%/*}"

# 结束旧的 service 循环与单次 switch
for _pat in \
	"$MODDIR/service.sh" \
	"$MODDIR/bin/qsc_switch.sh" \
	"/data/adb/modules/QSC_Battery/service.sh" \
	"/data/adb/modules/QSC_Battery/bin/qsc_switch.sh"
do
	pkill -f "$_pat" 2>/dev/null || true
done
sleep 1

# 已开机场景下直接后台跑 service（内部仍会做探测与主循环）
if [ -f "$MODDIR/service.sh" ]; then
	# Magisk 标记：避免被误认为未完成更新
	rm -f "$MODDIR/update" 2>/dev/null
	nohup sh "$MODDIR/service.sh" >/dev/null 2>&1 &
fi

echo "qsc: hotinstall done" >>/dev/kmsg 2>/dev/null || true
