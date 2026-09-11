package com.qsc.battery

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.ui.QscAppRoot
import com.qsc.battery.ui.theme.ColorMode
import com.qsc.battery.ui.theme.QscTheme
import com.qsc.battery.ui.theme.ThemeBootGuard
import com.qsc.battery.ui.theme.ThemeSettings
import com.qsc.battery.ui.theme.UiMode

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ThemeBootGuard.onProcessStart(this)
        enableEdgeToEdge()
        val container = (application as QscApp).container
        val forceSafe = ThemeBootGuard.consumeSafeMode(this)
        setContent {
            val settings by container.settingsRepository.settings.collectAsStateWithLifecycle(
                initialValue = ThemeSettings(),
            )
            val effective = remember(settings, forceSafe) {
                if (forceSafe) ThemeBootGuard.safeSettings(settings) else settings
            }
            QscTheme(settings = effective) {
                DisposableEffect(Unit) {
                    ThemeBootGuard.markThemeReady(this@MainActivity)
                    onDispose { }
                }
                LaunchedEffect(forceSafe) {
                    if (forceSafe) {
                        container.settingsRepository.setUiMode(UiMode.Pulse)
                        container.settingsRepository.setColorMode(ColorMode.SYSTEM)
                    }
                }
                QscAppRoot(container = container)
            }
        }
    }
}
