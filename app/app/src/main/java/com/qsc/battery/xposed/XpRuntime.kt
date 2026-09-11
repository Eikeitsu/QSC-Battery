package com.qsc.battery.xposed

/**
 * 由 XP 在加载本应用进程时置位，用于界面检测「框架是否已注入」。
 * 未启用 LSPosed / 未勾选本模块时保持 false。
 */
object XpRuntime {
    @JvmField
    @Volatile
    var isHooked: Boolean = false
}
