package com.qsc.battery.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.materialkolor.DynamicMaterialTheme
import com.materialkolor.PaletteStyle
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.darkColorScheme as miuixDark
import top.yukonga.miuix.kmp.theme.lightColorScheme as miuixLight

val LocalUiMode = staticCompositionLocalOf { UiMode.Miuix }
val LocalColorMode = staticCompositionLocalOf { ColorMode.SYSTEM }

@Composable
fun QscTheme(
    settings: ThemeSettings,
    content: @Composable () -> Unit,
) {
    val effective = settings.effectiveColorMode()
    val dark = when {
        effective.isSystem -> isSystemInDarkTheme()
        effective.isDark -> true
        else -> false
    }
    CompositionLocalProvider(
        LocalUiMode provides settings.uiMode,
        LocalColorMode provides effective,
    ) {
        val style = runCatching {
            PaletteStyle.valueOf(settings.paletteStyle.wire)
        }.getOrDefault(PaletteStyle.TonalSpot)

        val useDynamic = effective.isMonet ||
            settings.uiMode == UiMode.Material ||
            (settings.uiMode == UiMode.Miuix && settings.miuixMonet)

        val materialContent: @Composable () -> Unit = {
            if (useDynamic) {
                DynamicMaterialTheme(
                    seedColor = Color(settings.keyColor),
                    isDark = dark,
                    style = style,
                    animate = true,
                ) {
                    val scheme = MaterialTheme.colorScheme
                    val amoled = if (effective.isAmoled && dark) {
                        scheme.copy(background = Color.Black, surface = Color.Black)
                    } else {
                        scheme
                    }
                    MaterialTheme(colorScheme = amoled, content = content)
                }
            } else {
                MaterialTheme(
                    colorScheme = if (dark) darkColorScheme() else lightColorScheme(),
                    content = content,
                )
            }
        }

        when (settings.uiMode) {
            UiMode.Miuix -> MiuixTheme(colors = if (dark) miuixDark() else miuixLight()) {
                materialContent()
            }
            UiMode.Material -> materialContent()
        }
    }
}
