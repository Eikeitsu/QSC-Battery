package com.qsc.battery.xposed

/**
 * RemotePreferences 组名与键；文件侧与 Magisk / system_server 共用。
 * Magisk 读文件；APP 写 RemotePrefs 后同步 touch/rm 文件。
 */
object XpPrefs {
    const val REMOTE_GROUP = "qsc_xp"

    const val KEY_WAKE_ENABLED = "wake_enabled"
    const val KEY_VERBOSE_LOG = "verbose_log"
    const val KEY_XP_OFF = "xp_off"

    const val OFF_PATH = "/data/system/qsc_xp_off"
    const val NO_WAKE_PATH = "/data/system/qsc_xp_no_wake"
    const val VERBOSE_PATH = "/data/system/qsc_xp_verbose"
    const val ARM_PATH = "/data/system/qsc_xp_arm"
    const val WAKE_PATH = "/data/system/qsc_xp_wake"
    const val ALIVE_PATH = "/data/system/qsc_xp_alive"

    /** LSPosed / HyperCeiler：系统框架在 scope 里多为 system */
    val SYSTEM_SCOPE_PKGS = setOf("android", "system")
}
