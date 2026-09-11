package com.qsc.battery.ui.theme

import android.content.Context

/**
 * 若主题组合在上一进程渲染中崩溃，下次冷启动强制安全主题，避免「一开就闪退」。
 */
object ThemeBootGuard {
    private const val PREFS = "qsc_theme_boot"
    private const val KEY_PENDING = "theme_pending"
    private const val KEY_SAFE = "force_safe_theme"

    fun onProcessStart(context: Context) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (p.getBoolean(KEY_PENDING, false)) {
            p.edit().putBoolean(KEY_SAFE, true).putBoolean(KEY_PENDING, false).apply()
        } else {
            p.edit().putBoolean(KEY_PENDING, true).apply()
        }
    }

    fun markThemeReady(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PENDING, false)
            .apply()
    }

    fun consumeSafeMode(context: Context): Boolean {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!p.getBoolean(KEY_SAFE, false)) return false
        p.edit().putBoolean(KEY_SAFE, false).apply()
        return true
    }

    fun safeSettings(base: ThemeSettings): ThemeSettings = base.copy(
        uiMode = UiMode.Pulse,
        colorMode = ColorMode.SYSTEM,
    )
}
