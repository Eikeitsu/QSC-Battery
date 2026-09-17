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

    /** system_server 在部分机型写 /data/system 会失败；多路径探测注入 */
    val ALIVE_CANDIDATES: List<String> = listOf(
        ALIVE_PATH,
        "/data/local/tmp/qsc_xp_alive",
        "/cache/qsc_xp_alive",
        "/data/adb/modules/QSC_Battery/data/xp_alive",
    )

    /**
     * 现代 libxposed：system_server 用虚拟包名 **`system`**（官方 API）。
     * 只需勾选「系统框架」；不需要「Android系统」(android)。
     */
    const val PRIMARY_SCOPE = "system"

    fun scopeLabel(pkg: String): String = when (pkg.trim().lowercase()) {
        "system" -> "系统框架 (system) · system_server"
        "android" -> "Android系统 (android) · 非 system_server，请去掉"
        else -> pkg
    }

    fun hasPrimaryScope(scopeList: Collection<String>): Boolean =
        scopeList.any { it.trim().equals(PRIMARY_SCOPE, ignoreCase = true) }

    /** 仅识别 system；android 不算有效作用域。 */
    fun hasAnyFrameworkScope(scopeList: Collection<String>): Boolean = hasPrimaryScope(scopeList)
}
