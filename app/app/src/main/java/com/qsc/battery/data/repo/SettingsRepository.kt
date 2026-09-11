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
import com.qsc.battery.MainActivity
import com.qsc.battery.ui.theme.ColorMode
import com.qsc.battery.ui.theme.PaletteStyleName
import com.qsc.battery.ui.theme.ThemeSettings
import com.qsc.battery.ui.theme.UiMode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.settingsStore: DataStore<Preferences> by preferencesDataStore("qsc_settings")

class SettingsRepository(private val context: Context) {
    private object Keys {
        val uiMode = stringPreferencesKey("ui_mode")
        val themeMode = intPreferencesKey("theme_mode")
        val keyColor = intPreferencesKey("key_color")
        val colorStyle = stringPreferencesKey("color_style")
        val colorSpec = stringPreferencesKey("color_spec")
        val miuixMonet = booleanPreferencesKey("miuix_monet")
        val alternativeIcon = booleanPreferencesKey("alternative_icon")
        val onboardingDone = booleanPreferencesKey("onboarding_done")
        val xpPowerEvents = booleanPreferencesKey("xp_power_events")
        val skipRootWarning = booleanPreferencesKey("skip_root_warning")
    }

    val settings: Flow<ThemeSettings> = context.settingsStore.data.map { prefs ->
        ThemeSettings(
            uiMode = UiMode.fromValue(prefs[Keys.uiMode]),
            colorMode = ColorMode.fromValue(prefs[Keys.themeMode] ?: 0),
            keyColor = prefs[Keys.keyColor] ?: 0xFF0B6E4F.toInt(),
            paletteStyle = PaletteStyleName.fromWire(prefs[Keys.colorStyle]),
            colorSpec = prefs[Keys.colorSpec] ?: "SPEC_2021",
            miuixMonet = prefs[Keys.miuixMonet] ?: false,
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
        // LSPosed 可通过 XSharedPreferences 读取同名私有偏好
        context.getSharedPreferences("qsc_xp", Context.MODE_PRIVATE).edit()
            .putBoolean("xp_power_events", enabled)
            .apply()
    }

    suspend fun setUiMode(mode: UiMode) {
        context.settingsStore.edit { it[Keys.uiMode] = mode.value }
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

    suspend fun setMiuixMonet(enabled: Boolean) {
        context.settingsStore.edit { it[Keys.miuixMonet] = enabled }
    }

    suspend fun setAlternativeIcon(enabled: Boolean) {
        context.settingsStore.edit { it[Keys.alternativeIcon] = enabled }
        toggleLauncherIcon(enabled)
    }

    private fun toggleLauncherIcon(alternative: Boolean) {
        val pm = context.packageManager
        val main = ComponentName(context, MainActivity::class.java)
        val alt = ComponentName(context, "${context.packageName}.MainActivityAlt")
        pm.setComponentEnabledSetting(
            main,
            if (alternative) PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            else PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        pm.setComponentEnabledSetting(
            alt,
            if (alternative) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
