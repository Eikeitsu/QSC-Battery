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
    const val KEY_SCREEN_EDGE = "screen_edge"
    const val KEY_DOZE_EDGE = "doze_edge"
    const val KEY_BCAST_EDGE = "bcast_edge"

    const val OFF_PATH = "/data/system/qsc_xp_off"
    const val NO_WAKE_PATH = "/data/system/qsc_xp_no_wake"
    const val VERBOSE_PATH = "/data/system/qsc_xp_verbose"
    const val ARM_PATH = "/data/system/qsc_xp_arm"
    const val WAKE_PATH = "/data/system/qsc_xp_wake"
    const val ALIVE_PATH = "/data/system/qsc_xp_alive"

    /** 亮灭屏边沿开关（touch=开，默认关） */
    const val WANT_SCREEN_PATH = "/data/system/qsc_xp_want_screen"

    /** Doze 进出边沿开关（touch=开，默认关） */
    const val WANT_DOZE_PATH = "/data/system/qsc_xp_want_doze"

    /** 广播边沿开关（touch=开，默认关；动作列表见 BCAST_ACTIONS_PATH） */
    const val WANT_BCAST_PATH = "/data/system/qsc_xp_want_bcast"

    /** 亮灭屏：timestamp\\ton|off */
    const val SCREEN_PATH = "/data/system/qsc_xp_screen"

    /** Doze：timestamp\\tidle|active */
    const val DOZE_PATH = "/data/system/qsc_xp_doze"

    /** 广播：timestamp\\taction */
    const val BCAST_PATH = "/data/system/qsc_xp_bcast"

    /** 允许写入边沿的广播 Action（一行一个）；空则用内置低噪声默认集 */
    const val BCAST_ACTIONS_PATH = "/data/system/qsc_xp_bcast_actions"

    /** 当前前台包：timestamp\\tpkg（每次切换覆盖） */
    const val FG_PATH = "/data/system/qsc_xp_fg"

    /** 前台切换边沿通知（worker 打断睡眠用），内容同 FG 一行 */
    const val FG_EDGE_PATH = "/data/system/qsc_xp_fg_edge"

    /** 管理器前台边沿队列：每行 timestamp\\tenter|leave\\tpkg（追加；leave 的 pkg 为管理器） */
    const val VIEWER_PATH = "/data/system/qsc_xp_viewer"

    /** shell 同步的管理器包名列表（一行一个），供 XP 合并内置表 */
    const val VIEWER_PKGS_PATH = "/data/system/qsc_xp_viewer_pkgs"

    /** 可选：关闭前台包名总线（简介/游戏/App 停充的 XP 路径） */
    const val NO_VIEWER_PATH = "/data/system/qsc_xp_no_viewer"

    /** Magisk 同步：desc=0|1 / game=0|1 / app_stop=0|1 / idle=0|1 */
    const val FG_POLICY_PATH = "/data/system/qsc_xp_fg_policy"

    /** idle=1 时 touch；XP 热路径只做 exists，避免解析策略 */
    const val FG_IDLE_PATH = "/data/system/qsc_xp_fg_idle"

    /** 写盘连续失败后标记；Magisk 见此文件则勿再信任 XP ready */
    const val WRITE_DISABLED_PATH = "/data/system/qsc_xp_write_disabled"

    /** 游戏限流关注包（一行一个） */
    const val GAME_PKGS_PATH = "/data/system/qsc_xp_game_pkgs"

    /** App 停充关注包（一行一个） */
    const val STOP_PKGS_PATH = "/data/system/qsc_xp_stop_pkgs"

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

    fun hasPrimaryScope(scopeList: Collection<String>): Boolean = scopeList.any { it.trim().equals(PRIMARY_SCOPE, ignoreCase = true) }

    /** 仅识别 system；android 不算有效作用域。 */
    fun hasAnyFrameworkScope(scopeList: Collection<String>): Boolean = hasPrimaryScope(scopeList)
}
