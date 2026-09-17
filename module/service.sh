#!/system/bin/sh
# Magisk late_start service 入口（文件名冻结）
MODDIR=${0%/*}
. "$MODDIR/bin/common.sh"
. "$LIBDIR/service_boot.sh"
while true ; do
	. "$LIBDIR/service_loop.sh"
done
