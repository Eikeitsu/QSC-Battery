package com.qsc.battery.core

object ModulePaths {
    const val MODULE_ID = "QSC_Battery"
    const val MODDIR = "/data/adb/modules/$MODULE_ID"
    const val CONF = "$MODDIR/config/config.conf"
    const val CURRENT = "$MODDIR/config/current.json"
    const val PROFILES = "$MODDIR/config/profiles.json"
    const val DATADIR = "$MODDIR/data"
    const val MODULE_OFF_FLAG = "$DATADIR/module_off"
    const val LOG_FILE = "$DATADIR/log.log"
    const val CHARGE_EVENTS = "$DATADIR/charge_events.log"
    const val CHARGE_HISTORY = "$DATADIR/charge_history.csv"

    /** LSPosed XP 稀疏日志（system_server 多路径写；Root 合并读） */
    const val XP_LOG = "/data/system/qsc_xp.log"
    const val XP_LOG_TMP = "/data/local/tmp/qsc_xp.log"
    const val XP_LOG_CACHE = "/cache/qsc_xp.log"

    /** Magisk 侧镜像 / 边沿事件（模块 data，Root 必可读） */
    const val XP_LOG_MODULE = "$DATADIR/xp.log"
    val XP_LOG_CANDIDATES: List<String> = listOf(XP_LOG, XP_LOG_TMP, XP_LOG_CACHE, XP_LOG_MODULE)
    const val HEALTH_HISTORY = "$DATADIR/health_history.csv"
    const val POWER_SWITCH_FLAG = "$DATADIR/power_switch"
    const val MODULE_PROP = "$MODDIR/module.prop"
    const val COMMON_SH = "$MODDIR/bin/common.sh"
    const val BATTERY_INFO = "$MODDIR/bin/lib/battery_info.sh"
    const val QSCD_FETCH = "$MODDIR/bin/qscd_fetch.sh"
    const val QSCD = "$MODDIR/bin/qscd"
    const val PROFILES_DIR = "$DATADIR/profiles"
    const val HOT_UPDATE_LOCK = "/data/adb/qsc/hot_update/lock"

    /** APP CLI 刷模块前 touch；customize.sh 读到则跳过音量键 */
    const val INSTALL_AUTO = "/data/adb/qsc/install_auto"
    const val STATUS_HELPER = "$MODDIR/bin/qsc_status.sh"
}
