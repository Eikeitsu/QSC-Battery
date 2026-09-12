package com.qsc.battery.data.repo

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.qsc.battery.ui.theme.ColorMode
import com.qsc.battery.ui.theme.PaletteStyleName
import com.qsc.battery.ui.theme.ThemeSettings
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.settingsStore: DataStore<Preferences> by preferencesDataStore("qsc_settings")

class SettingsRepository(private val context: Context) {
    private object Keys {
        val themeMode = intPreferencesKey("theme_mode")
        val keyColor = intPreferencesKey("key_color")
        val colorStyle = stringPreferencesKey("color_style")
        val colorSpec = stringPreferencesKey("color_spec")
        val alternativeIcon = booleanPreferencesKey("alternative_icon")
        val onboardingDone = booleanPreferencesKey("onboarding_done")
        val xpPowerEvents = booleanPreferencesKey("xp_power_events")
    }

    // 使用 namespace，避免 debug 的 applicationIdSuffix 拼错 alias
    private val defaultLauncher = ComponentName(context, "com.qsc.battery.MainActivityDefault")
    private val altLauncher = ComponentName(context, "com.qsc.battery.MainActivityAlt")

    val settings: Flow<ThemeSettings> = context.settingsStore.data.map { prefs ->
        ThemeSettings(
            colorMode = ColorMode.fromValue(prefs[Keys.themeMode] ?: 0),
            keyColor = prefs[Keys.keyColor] ?: 0xFF0B6E4F.toInt(),
            paletteStyle = PaletteStyleName.fromWire(prefs[Keys.colorStyle]),
            colorSpec = prefs[Keys.colorSpec] ?: "SPEC_2021",
            alternativeIcon = prefs[Keys.alternativeIcon] ?: false,
        )
    }

    val onboardingDone: Flow<Boolean> = context.settingsStore.data.map {
        it[Keys.onboardingDone] ?: false
    }

    val xpPowerEventsEnabled: Flow<Boolean> = context.settingsStore.data.map {
        it[Keys.xpPowerEvents] ?: true
    }

    suspend fun setOnboardingDone(done: Boolean) {
        context.settingsStore.edit { it[Keys.onboardingDone] = done }
    }

    suspend fun setXpPowerEvents(enabled: Boolean) {
        context.settingsStore.edit { it[Keys.xpPowerEvents] = enabled }
        context.getSharedPreferences("qsc_xp", Context.MODE_PRIVATE).edit()
            .putBoolean("xp_power_events", enabled)
            .apply()
    }

    suspend fun setColorMode(mode: ColorMode) {
        context.settingsStore.edit { it[Keys.themeMode] = mode.value }
    }

    suspend fun setKeyColor(color: Int) {
        context.settingsStore.edit { it[Keys.keyColor] = color }
    }

    suspend fun setPaletteStyle(style: PaletteStyleName) {
        context.settingsStore.edit { it[Keys.colorStyle] = style.wire }
    }

    suspend fun setColorSpec(spec: String) {
        context.settingsStore.edit { it[Keys.colorSpec] = spec }
    }

    suspend fun setAlternativeIcon(enabled: Boolean) {
        context.settingsStore.edit { it[Keys.alternativeIcon] = enabled }
        applyLauncherIcon(enabled)
    }

    /** 启动时按偏好同步 alias，避免升级后图标状态丢失。 */
    suspend fun syncLauncherIcon() {
        val enabled = context.settingsStore.data.first()[Keys.alternativeIcon] ?: false
        applyLauncherIcon(enabled)
    }

    private fun applyLauncherIcon(alternative: Boolean) {
        val pm = context.packageManager
        runCatching {
            pm.setComponentEnabledSetting(
                defaultLauncher,
                if (alternative) {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                },
                PackageManager.DONT_KILL_APP,
            )
            pm.setComponentEnabledSetting(
                altLauncher,
                if (alternative) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                },
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
