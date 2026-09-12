package com.qsc.battery.core

object ModulePaths {
    const val MODULE_ID = "QSC_Battery"
    const val MODDIR = "/data/adb/modules/$MODULE_ID"
    const val CONF = "$MODDIR/config/config.conf"
    const val CURRENT = "$MODDIR/config/current.json"
    const val PROFILES = "$MODDIR/config/profiles.json"
    const val DATADIR = "$MODDIR/data"
    const val OFF_FLAG = "$DATADIR/off_qsc"
    const val LOG_FILE = "$DATADIR/log.log"
    const val CHARGE_EVENTS = "$DATADIR/charge_events.log"
    const val CHARGE_HISTORY = "$DATADIR/charge_history.csv"
    /** LSPosed XP 稀疏日志（system_server 写入，Root 可读） */
    const val XP_LOG = "/data/system/qsc_xp.log"
    const val HEALTH_HISTORY = "$DATADIR/health_history.csv"
    const val POWER_SWITCH_FLAG = "$DATADIR/power_switch"
    const val MODULE_PROP = "$MODDIR/module.prop"
    const val COMMON_SH = "$MODDIR/bin/common.sh"
    const val BATTERY_INFO = "$MODDIR/bin/lib/battery_info.sh"
    const val QSCD_FETCH = "$MODDIR/bin/qscd_fetch.sh"
    const val QSCD = "$MODDIR/bin/qscd"
    const val PROFILES_DIR = "$DATADIR/profiles"
    const val HOT_UPDATE_LOCK = "/data/adb/qsc/hot_update/lock"
    const val STATUS_HELPER = "$MODDIR/bin/qsc_status.sh"
}
