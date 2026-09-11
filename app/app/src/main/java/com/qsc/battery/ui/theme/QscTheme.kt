package com.qsc.battery.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.materialkolor.PaletteStyle
import com.materialkolor.rememberDynamicColorScheme
import com.qsc.battery.ui.design.charge.ChargeThemeProvider
import com.qsc.battery.ui.design.charge.chargeDarkColors
import com.qsc.battery.ui.design.charge.chargeLightColors

val LocalColorMode = staticCompositionLocalOf { ColorMode.SYSTEM }

@Composable
fun QscTheme(
    settings: ThemeSettings,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val mode = settings.colorMode
    val dark = when {
        mode.isSystem -> isSystemInDarkTheme()
        mode.isDark -> true
        else -> false
    }

    LaunchedEffect(settings.colorMode, settings.keyColor) {
        ThemeBootGuard.markThemeReady(context)
    }

    val seed = Color(settings.keyColor)
    val style = runCatching {
        PaletteStyle.valueOf(settings.paletteStyle.wire)
    }.getOrDefault(PaletteStyle.TonalSpot)
    val dynamicScheme = rememberDynamicColorScheme(
        seedColor = seed,
        isDark = dark,
        isAmoled = mode.isAmoled && dark,
        style = style,
    )
    val accent = if (mode.isMonet) dynamicScheme.primary else seed
    val colors = if (dark) {
        chargeDarkColors(accent = accent, amoled = mode.isAmoled)
    } else {
        chargeLightColors(accent = accent)
    }

    val m3 = if (dark) {
        darkColorScheme(
            primary = accent,
            background = colors.background,
            surface = colors.surface,
            onPrimary = colors.onAccent,
            onBackground = colors.ink,
            onSurface = colors.ink,
        )
    } else {
        lightColorScheme(
            primary = accent,
            background = colors.background,
            surface = colors.surface,
            onPrimary = colors.onAccent,
            onBackground = colors.ink,
            onSurface = colors.ink,
        )
    }

    CompositionLocalProvider(LocalColorMode provides mode) {
        MaterialTheme(colorScheme = m3) {
            ChargeThemeProvider(colors = colors, content = content)
        }
    }
}
