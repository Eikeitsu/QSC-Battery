package com.qsc.battery.icon

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.BatteryManager
import com.qsc.battery.data.repo.SettingsRepository

/**
 * 桌面图标按电量 10% 档切换（activity-alias）。
 * 电池风格与环形风格均可动态；矢量资源，体积很小。
 * 仅在调用方主动触发时读取电量；不注册 BATTERY_CHANGED。
 */
object LauncherIconController {
    private const val PREFS = "qsc_launcher_icon"
    private const val KEY_APPLIED = "applied_key"

    /** 0,10,...,100 */
    val BUCKETS: IntArray = IntArray(11) { it * 10 }

    fun bucketForLevel(level: Int): Int {
        val pct = level.coerceIn(0, 100)
        return (pct / 10) * 10
    }

    fun readBatteryPercent(context: Context): Int {
        val bm = context.getSystemService(BatteryManager::class.java) ?: return 50
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (pct in 0..100) pct else 50
    }

    /**
     * @param force 忽略缓存，强制重新 setComponentEnabledSetting
     */
    fun apply(
        context: Context,
        alternative: Boolean,
        dynamic: Boolean,
        force: Boolean = false,
    ) {
        val app = context.applicationContext
        val level = readBatteryPercent(app)
        val bucket = bucketForLevel(level)
        val key = when {
            alternative && !dynamic -> "alt"
            alternative && dynamic -> "alt_$bucket"
            !dynamic -> "default"
            else -> "bat_$bucket"
        }
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!force && prefs.getString(KEY_APPLIED, null) == key) return

        val pm = app.packageManager
        val all = buildList {
            add("com.qsc.battery.MainActivityDefault")
            add("com.qsc.battery.MainActivityAlt")
            for (b in BUCKETS) {
                add("com.qsc.battery.MainActivityBat%02d".format(b))
                add("com.qsc.battery.MainActivityAlt%02d".format(b))
            }
        }

        val active = when {
            alternative && !dynamic -> "com.qsc.battery.MainActivityAlt"
            alternative && dynamic -> "com.qsc.battery.MainActivityAlt%02d".format(bucket)
            !dynamic -> "com.qsc.battery.MainActivityDefault"
            else -> "com.qsc.battery.MainActivityBat%02d".format(bucket)
        }

        runCatching {
            for (name in all) {
                val state = if (name == active) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                }
                pm.setComponentEnabledSetting(
                    ComponentName(app, name),
                    state,
                    PackageManager.DONT_KILL_APP,
                )
            }
            prefs.edit().putString(KEY_APPLIED, key).apply()
        }
    }

    /** 启动 / 回前台 / 稀疏电量事件：按 DataStore 偏好同步。 */
    suspend fun syncFromSettings(context: Context, settings: SettingsRepository, force: Boolean = false) {
        val alternative = settings.alternativeIconEnabled()
        val dynamic = settings.dynamicBatteryIconEnabled()
        apply(context, alternative = alternative, dynamic = dynamic, force = force)
    }
}
