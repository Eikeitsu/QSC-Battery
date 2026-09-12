package com.qsc.battery.icon

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.BatteryManager
import com.qsc.battery.data.repo.SettingsRepository

/**
 * 桌面图标按电量约 20% 档 + 是否充电切换（activity-alias）。
 * 桌面图标无法运行时改矢量颜色，故用脚本逻辑生成少量档位资源；
 * 充电时闪电为黄色。不注册 BATTERY_CHANGED，仅稀疏触发刷新。
 */
object LauncherIconController {
    private const val PREFS = "qsc_launcher_icon"
    private const val KEY_APPLIED = "applied_key"

    /** 0,20,...,100 */
    val BUCKETS: IntArray = intArrayOf(0, 20, 40, 60, 80, 100)

    fun bucketForLevel(level: Int): Int {
        val pct = level.coerceIn(0, 100)
        if (pct >= 100) return 100
        return (pct / 20) * 20
    }

    fun readBatteryPercent(context: Context): Int {
        val bm = context.getSystemService(BatteryManager::class.java) ?: return 50
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (pct in 0..100) pct else 50
    }

    fun isDeviceCharging(context: Context): Boolean {
        val bm = context.getSystemService(BatteryManager::class.java) ?: return false
        return bm.isCharging
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
        val charging = isDeviceCharging(app)
        val key = when {
            alternative && !dynamic -> "alt"
            alternative && dynamic -> "alt_${bucket}_${if (charging) "c" else "n"}"
            !dynamic -> "default"
            else -> "bat_${bucket}_${if (charging) "c" else "n"}"
        }
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!force && prefs.getString(KEY_APPLIED, null) == key) return

        val pm = app.packageManager
        val all = buildList {
            add("com.qsc.battery.MainActivityDefault")
            add("com.qsc.battery.MainActivityAlt")
            for (b in BUCKETS) {
                val tag = "%02d".format(b)
                add("com.qsc.battery.MainActivityBat$tag")
                add("com.qsc.battery.MainActivityBat${tag}c")
                add("com.qsc.battery.MainActivityAlt$tag")
                add("com.qsc.battery.MainActivityAlt${tag}c")
            }
        }

        val active = when {
            alternative && !dynamic -> "com.qsc.battery.MainActivityAlt"
            alternative && dynamic -> {
                val tag = "%02d".format(bucket)
                if (charging) "com.qsc.battery.MainActivityAlt${tag}c"
                else "com.qsc.battery.MainActivityAlt$tag"
            }
            !dynamic -> "com.qsc.battery.MainActivityDefault"
            else -> {
                val tag = "%02d".format(bucket)
                if (charging) "com.qsc.battery.MainActivityBat${tag}c"
                else "com.qsc.battery.MainActivityBat$tag"
            }
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

    suspend fun syncFromSettings(context: Context, settings: SettingsRepository, force: Boolean = false) {
        val alternative = settings.alternativeIconEnabled()
        val dynamic = settings.dynamicBatteryIconEnabled()
        apply(context, alternative = alternative, dynamic = dynamic, force = force)
    }
}
