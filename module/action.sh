#!/system/bin/sh

MODDIR=${0%/*}

# WebUI / 模块管理页触发时刷新权限
if [ -f "$MODDIR/bin/common.sh" ]; then
	. "$MODDIR/bin/common.sh"
	chmod 0755 "$BINDIR"/*.sh 2>/dev/null
	chmod 0644 "$CONF" 2>/dev/null
	find "$MODDIR/webroot" -type f -exec chmod 0644 {} \; 2>/dev/null
fi
