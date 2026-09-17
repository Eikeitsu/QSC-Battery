package com.qsc.battery.icon

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.BatteryManager
import com.qsc.battery.data.repo.SettingsRepository

/**
 * 桌面图标按电量约 10% 档 + 是否充电切换（activity-alias）。
 *
 * 关键：必须先启用目标 alias，再禁用其它；否则部分机型会在短暂「零启动器入口」
 * 时把图标藏掉，甚至把刚打开的界面搞没。失败时强制回退 MainActivityDefault。
 */
object LauncherIconController {
    private const val PREFS = "qsc_launcher_icon"
    private const val KEY_APPLIED = "applied_key"

    private const val PKG = "com.qsc.battery"
    private const val DEFAULT_ALIAS = "$PKG.MainActivityDefault"

    /** 0,10,...,100 */
    val BUCKETS: IntArray = IntArray(11) { it * 10 }

    fun bucketForLevel(level: Int): Int {
        val pct = level.coerceIn(0, 100)
        if (pct >= 100) return 100
        return (pct / 10) * 10
    }

    fun readBatteryPercent(context: Context): Int {
        val bm = context.getSystemService(BatteryManager::class.java) ?: return 50
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (pct in 0..100) pct else 50
    }

    fun isDeviceCharging(context: Context): Boolean {
        val bm = context.getSystemService(BatteryManager::class.java) ?: return false
        return runCatching { bm.isCharging }.getOrDefault(false)
    }

    private fun allAliases(): List<String> = buildList {
        add(DEFAULT_ALIAS)
        add("$PKG.MainActivityAlt")
        for (b in BUCKETS) {
            val tag = "%02d".format(b)
            add("$PKG.MainActivityBat$tag")
            add("$PKG.MainActivityBat${tag}c")
            add("$PKG.MainActivityAlt$tag")
            add("$PKG.MainActivityAlt${tag}c")
        }
    }

    private fun resolveActive(alternative: Boolean, dynamic: Boolean, bucket: Int, charging: Boolean): String {
        val tag = "%02d".format(bucket)
        return when {
            alternative && !dynamic -> "$PKG.MainActivityAlt"
            alternative && dynamic && charging -> "$PKG.MainActivityAlt${tag}c"
            alternative && dynamic -> "$PKG.MainActivityAlt$tag"
            !dynamic -> DEFAULT_ALIAS
            charging -> "$PKG.MainActivityBat${tag}c"
            else -> "$PKG.MainActivityBat$tag"
        }
    }

    private fun setEnabled(pm: PackageManager, app: Context, name: String, enabled: Boolean) {
        val state = if (enabled) {
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

    private fun isEffectivelyEnabled(pm: PackageManager, app: Context, name: String): Boolean = when (pm.getComponentEnabledSetting(ComponentName(app, name))) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true

        PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false

        // DEFAULT：走清单默认值——仅 Default alias 在清单里 enabled=true
        else -> name == DEFAULT_ALIAS
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
        if (!force && prefs.getString(KEY_APPLIED, null) == key) {
            // 缓存命中仍校验：避免历史 bug 留下「全部禁用」状态
            val pm = app.packageManager
            val active = resolveActive(alternative, dynamic, bucket, charging)
            if (isEffectivelyEnabled(pm, app, active)) return
        }

        val pm = app.packageManager
        val all = allAliases()
        var active = resolveActive(alternative, dynamic, bucket, charging)
        if (active !in all) active = DEFAULT_ALIAS

        runCatching {
            // 1) 先启用目标，保证任意时刻至少有一个 LAUNCHER
            setEnabled(pm, app, active, enabled = true)
            // 2) 再关其它
            for (name in all) {
                if (name != active) setEnabled(pm, app, name, enabled = false)
            }
            // 3) 校验；失败则回退默认图标
            if (!isEffectivelyEnabled(pm, app, active)) {
                setEnabled(pm, app, DEFAULT_ALIAS, enabled = true)
                for (name in all) {
                    if (name != DEFAULT_ALIAS) setEnabled(pm, app, name, enabled = false)
                }
                prefs.edit().putString(KEY_APPLIED, "default").apply()
                return@runCatching
            }
            prefs.edit().putString(KEY_APPLIED, key).apply()
        }.onFailure {
            runCatching {
                setEnabled(pm, app, DEFAULT_ALIAS, enabled = true)
                for (name in all) {
                    if (name != DEFAULT_ALIAS) setEnabled(pm, app, name, enabled = false)
                }
                prefs.edit().putString(KEY_APPLIED, "default").apply()
            }
        }
    }

    /** 紧急恢复：只开默认桌面入口（升级/排查用） */
    fun restoreDefaultLauncher(context: Context) {
        apply(context, alternative = false, dynamic = false, force = true)
    }

    suspend fun syncFromSettings(context: Context, settings: SettingsRepository, force: Boolean = false) {
        val alternative = settings.alternativeIconEnabled()
        val dynamic = settings.dynamicBatteryIconEnabled()
        apply(context, alternative = alternative, dynamic = dynamic, force = force)
    }
}
