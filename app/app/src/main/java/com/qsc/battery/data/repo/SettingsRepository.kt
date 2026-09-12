package com.qsc.battery.data.repo

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.qsc.battery.icon.LauncherIconController
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
        val dynamicBatteryIcon = booleanPreferencesKey("dynamic_battery_icon")
        val onboardingDone = booleanPreferencesKey("onboarding_done")
        val xpPowerEvents = booleanPreferencesKey("xp_power_events")
    }

    val settings: Flow<ThemeSettings> = context.settingsStore.data.map { prefs ->
        ThemeSettings(
            colorMode = ColorMode.fromValue(prefs[Keys.themeMode] ?: 0),
            keyColor = prefs[Keys.keyColor] ?: 0xFF0B6E4F.toInt(),
            paletteStyle = PaletteStyleName.fromWire(prefs[Keys.colorStyle]),
            colorSpec = prefs[Keys.colorSpec] ?: "SPEC_2021",
            alternativeIcon = prefs[Keys.alternativeIcon] ?: false,
            // 默认关：避免安装后立即切换 alias 导致部分桌面「无图标」
            dynamicBatteryIcon = prefs[Keys.dynamicBatteryIcon] ?: false,
        )
    }

    val onboardingDone: Flow<Boolean> = context.settingsStore.data.map {
        it[Keys.onboardingDone] ?: false
    }

    val xpPowerEventsEnabled: Flow<Boolean> = context.settingsStore.data.map {
        it[Keys.xpPowerEvents] ?: true
    }

    suspend fun alternativeIconEnabled(): Boolean =
        context.settingsStore.data.first()[Keys.alternativeIcon] ?: false

    suspend fun dynamicBatteryIconEnabled(): Boolean =
        context.settingsStore.data.first()[Keys.dynamicBatteryIcon] ?: false

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
        val dynamic = dynamicBatteryIconEnabled()
        LauncherIconController.apply(
            context,
            alternative = enabled,
            dynamic = dynamic,
            force = true,
        )
    }

    suspend fun setDynamicBatteryIcon(enabled: Boolean) {
        context.settingsStore.edit { it[Keys.dynamicBatteryIcon] = enabled }
        val alternative = alternativeIconEnabled()
        LauncherIconController.apply(
            context,
            alternative = alternative,
            dynamic = enabled,
            force = true,
        )
    }

    /** 启动时按偏好同步 alias，避免升级后图标状态丢失。 */
    suspend fun syncLauncherIcon(force: Boolean = false) {
        LauncherIconController.syncFromSettings(context, this, force = force)
    }
}
