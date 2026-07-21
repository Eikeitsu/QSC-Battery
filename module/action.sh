#!/system/bin/sh

MODDIR=${0%/*}

echo "========================================"
echo " QSC 定量停充 · Action"
echo "========================================"

if [ ! -f "$MODDIR/bin/common.sh" ]; then
	echo "[错误] 缺少 bin/common.sh，请重新安装模块"
	exit 1
fi

. "$MODDIR/bin/common.sh"

echo "[1/4] 刷新脚本权限..."
chmod 0755 "$BINDIR"/*.sh 2>/dev/null
echo "  bin/*.sh -> 0755"

echo "[2/4] 刷新配置权限..."
if [ -f "$CONF" ]; then
	chmod 0644 "$CONF" 2>/dev/null
	echo "  config.conf -> 0644"
else
	echo "  警告: 未找到 config.conf"
fi

echo "[3/4] 刷新 WebUI 文件权限..."
if [ -d "$MODDIR/webroot" ]; then
	find "$MODDIR/webroot" -type f -exec chmod 0644 {} \; 2>/dev/null
	find "$MODDIR/webroot" -type d -exec chmod 0755 {} \; 2>/dev/null
	echo "  webroot 已处理"
else
	echo "  webroot 未安装（核心停充功能不受影响）"
fi

echo "[4/4] 检查关键文件..."
[ -f "$BINDIR/qsc_switch.sh" ] && echo "  qsc_switch.sh: OK" || echo "  qsc_switch.sh: 缺失"
[ -f "$CONF" ] && echo "  config.conf: OK" || echo "  config.conf: 缺失"
[ -f "$MODDIR/webroot/index.html" ] && echo "  webroot/index.html: OK" || echo "  webroot/index.html: 未安装"
[ -f "$OFF_FLAG" ] && echo "  模块状态: 已关闭 (存在 off_qsc)" || echo "  模块状态: 开启"

echo "========================================"
echo " Action 完成：权限已刷新"
[ -f "$MODDIR/webroot/index.html" ] && echo " 可重新打开 WebUI 查看状态"
echo "========================================"
