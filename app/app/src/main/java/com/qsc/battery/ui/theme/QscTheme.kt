package com.qsc.battery.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.materialkolor.PaletteStyle
import com.materialkolor.rememberDynamicColorScheme

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

    CompositionLocalProvider(LocalColorMode provides mode) {
        val style = runCatching {
            PaletteStyle.valueOf(settings.paletteStyle.wire)
        }.getOrDefault(PaletteStyle.TonalSpot)

        val dynamicScheme = rememberDynamicColorScheme(
            seedColor = Color(settings.keyColor),
            isDark = dark,
            isAmoled = mode.isAmoled && dark,
            style = style,
        )
        val seed = Color(settings.keyColor)
        val staticScheme = if (dark) {
            if (mode.isAmoled) {
                darkColorScheme(primary = seed, surface = Color.Black, background = Color.Black)
            } else {
                darkColorScheme(primary = seed)
            }
        } else {
            lightColorScheme(primary = seed)
        }
        val colorScheme = if (mode.isMonet) dynamicScheme else staticScheme

        MaterialTheme(
            colorScheme = colorScheme,
            typography = voltTypography(),
            shapes = voltShapes(),
            content = content,
        )
    }
}

private fun voltTypography(): Typography {
    val base = Typography()
    return base.copy(
        displayLarge = TextStyle(
            fontFamily = FontFamily.SansSerif,
            fontWeight = FontWeight.Bold,
            fontSize = 52.sp,
            lineHeight = 56.sp,
            letterSpacing = (-0.5).sp,
        ),
        headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.SemiBold, fontSize = 26.sp),
        headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.SemiBold, fontSize = 22.sp),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 20.sp),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.Medium, fontSize = 16.sp),
        bodyLarge = base.bodyLarge.copy(fontSize = 16.sp, lineHeight = 24.sp),
        bodyMedium = base.bodyMedium.copy(fontSize = 14.sp, lineHeight = 20.sp),
        labelLarge = base.labelLarge.copy(fontWeight = FontWeight.Medium),
    )
}

private fun voltShapes() = Shapes(
    extraSmall = RoundedCornerShape(10.dp),
    small = RoundedCornerShape(14.dp),
    medium = RoundedCornerShape(18.dp),
    large = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(32.dp),
)
