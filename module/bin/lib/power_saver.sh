#!/system/bin/sh
# 省电主循环辅助：插电判定 / 跳过轮询 / 事件等待
# 实现拆到 power_saver_*.sh；本文件保持稳定入口。
. "$LIBDIR/power_saver_core.sh"
. "$LIBDIR/power_saver_plugged.sh"
. "$LIBDIR/power_policy.sh"
. "$LIBDIR/power_saver_decide.sh"
. "$LIBDIR/power_saver_idle.sh"
