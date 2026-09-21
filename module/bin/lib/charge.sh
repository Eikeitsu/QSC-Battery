#!/system/bin/sh
# 充电节点写入：用户 power_switch + 通用 fallback + MCA / preferred 优先
# 实现拆到 charge_*.sh；本文件保持为 common.sh 的稳定入口。
. "$LIBDIR/charge_nodes.sh"
. "$LIBDIR/charge_write.sh"
. "$LIBDIR/charge_mca.sh"
. "$LIBDIR/charge_unplug.sh"
. "$LIBDIR/charge_restore.sh"
[ -f "$LIBDIR/hot_update_charge.sh" ] && . "$LIBDIR/hot_update_charge.sh"
