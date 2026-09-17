#!/system/bin/sh
# 电流控制（可选）：限流 / 旁路 / 写入
# 实现拆到 current_*.sh；安装时可整体删除本入口。
. "$LIBDIR/current_limits.sh"
. "$LIBDIR/current_bypass.sh"
. "$LIBDIR/current_apply.sh"
