#!/system/bin/sh
# 热更新事务：apply / finalize
# 实现拆到 hot_update_*.sh；本文件保持稳定入口。
. "$LIBDIR/hot_update_txn.sh"
. "$LIBDIR/hot_update_verify.sh"
