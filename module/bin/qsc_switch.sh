#!/system/bin/sh
# 停充主循环：读配置/电量 → 判定 → 调用 lib/charge 写节点
# 实现拆到 lib/switch_*.sh；本文件名冻结。
. "${0%/*}/common.sh"
. "$LIBDIR/switch_prelude.sh"
. "$LIBDIR/switch_charge_full.sh"
. "$LIBDIR/switch_eval.sh"
. "$LIBDIR/switch_apply.sh"
