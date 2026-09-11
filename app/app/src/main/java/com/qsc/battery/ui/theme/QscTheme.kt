package com.qsc.battery.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.materialkolor.PaletteStyle
import com.materialkolor.rememberDynamicColorScheme
import com.moriafly.salt.ui.SaltConfigs
import com.moriafly.salt.ui.SaltDynamicColors
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.darkSaltColors
import com.moriafly.salt.ui.lightSaltColors

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
    val highlight = if (mode.isMonet) dynamicScheme.primary else seed

    val light = lightSaltColors(highlight = highlight)
    val darkBase = darkSaltColors(highlight = highlight)
    val darkColors = if (mode.isAmoled && dark) {
        darkBase.copy(background = Color.Black)
    } else {
        darkBase
    }

    CompositionLocalProvider(LocalColorMode provides mode) {
        SaltTheme(
            configs = SaltConfigs.default(isDarkTheme = dark),
            dynamicColors = SaltDynamicColors(light = light, dark = darkColors),
            content = content,
        )
    }
}
