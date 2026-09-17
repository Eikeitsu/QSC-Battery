package com.qsc.battery

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.ui.QscAppRoot
import com.qsc.battery.ui.theme.ColorMode
import com.qsc.battery.ui.theme.QscTheme
import com.qsc.battery.ui.theme.ThemeBootGuard
import com.qsc.battery.ui.theme.ThemeSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val iconScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onStart() {
        super.onStart()
        val app = application as? QscApp ?: return
        // 打开应用时低频刷新电量档位（档未变则 no-op）
        iconScope.launch {
            app.container.settingsRepository.syncLauncherIcon(force = false)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ThemeBootGuard.onProcessStart(this)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(
                lightScrim = Color.Transparent.toArgb(),
                darkScrim = Color.Transparent.toArgb(),
            ),
            navigationBarStyle = SystemBarStyle.auto(
                lightScrim = Color.Transparent.toArgb(),
                darkScrim = Color.Transparent.toArgb(),
            ),
        )
        val container = (application as QscApp).container
        val forceSafe = ThemeBootGuard.consumeSafeMode(this)
        setContent {
            val settings by container.settingsRepository.settings.collectAsStateWithLifecycle(
                initialValue = ThemeSettings(),
            )
            val effective = remember(settings, forceSafe) {
                if (forceSafe) ThemeBootGuard.safeSettings(settings) else settings
            }
            val dark = when {
                effective.colorMode.isSystem -> isSystemInDarkTheme()
                effective.colorMode.isDark -> true
                else -> false
            }
            DisposableEffect(dark) {
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
                onDispose { }
            }
            QscTheme(settings = effective) {
                DisposableEffect(Unit) {
                    ThemeBootGuard.markThemeReady(this@MainActivity)
                    onDispose { }
                }
                LaunchedEffect(forceSafe) {
                    if (forceSafe) {
                        container.settingsRepository.setColorMode(ColorMode.SYSTEM)
                    }
                }
                QscAppRoot(container = container)
            }
        }
    }
}
