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

val LocalUiMode = staticCompositionLocalOf { UiMode.Pulse }
val LocalColorMode = staticCompositionLocalOf { ColorMode.SYSTEM }

@Composable
fun QscTheme(
    settings: ThemeSettings,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val effective = settings.effectiveColorMode()
    val dark = when {
        effective.isSystem -> isSystemInDarkTheme()
        effective.isDark -> true
        else -> false
    }

    LaunchedEffect(settings.uiMode, settings.colorMode, settings.keyColor) {
        ThemeBootGuard.markThemeReady(context)
    }

    CompositionLocalProvider(
        LocalUiMode provides settings.uiMode,
        LocalColorMode provides effective,
    ) {
        val style = runCatching {
            PaletteStyle.valueOf(settings.paletteStyle.wire)
        }.getOrDefault(PaletteStyle.TonalSpot)

        val typography = when (settings.uiMode) {
            UiMode.Pulse -> pulseTypography()
            UiMode.Ledger -> ledgerTypography()
        }
        val shapes = when (settings.uiMode) {
            UiMode.Pulse -> pulseShapes()
            UiMode.Ledger -> ledgerShapes()
        }

        val dynamicScheme = rememberDynamicColorScheme(
            seedColor = Color(settings.keyColor),
            isDark = dark,
            isAmoled = effective.isAmoled && dark,
            style = style,
        )
        val seed = Color(settings.keyColor)
        val staticScheme = if (dark) {
            if (effective.isAmoled) {
                darkColorScheme(primary = seed, surface = Color.Black, background = Color.Black)
            } else {
                darkColorScheme(primary = seed)
            }
        } else {
            lightColorScheme(primary = seed)
        }
        val colorScheme = if (effective.isMonet) dynamicScheme else staticScheme

        MaterialTheme(
            colorScheme = colorScheme,
            typography = typography,
            shapes = shapes,
            content = content,
        )
    }
}

private fun pulseTypography(): Typography {
    val base = Typography()
    return base.copy(
        displayLarge = TextStyle(
            fontFamily = FontFamily.SansSerif,
            fontWeight = FontWeight.Bold,
            fontSize = 48.sp,
            lineHeight = 52.sp,
        ),
        headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 30.sp),
        headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.SemiBold, fontSize = 26.sp),
        headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.SemiBold, fontSize = 22.sp),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
        bodyLarge = base.bodyLarge.copy(fontSize = 16.sp, lineHeight = 24.sp),
    )
}

private fun ledgerTypography(): Typography {
    val base = Typography()
    return base.copy(
        headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.Medium, fontSize = 20.sp),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Medium, fontSize = 18.sp),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.Medium, fontSize = 15.sp),
        bodyLarge = base.bodyLarge.copy(fontSize = 15.sp, lineHeight = 20.sp),
        bodyMedium = base.bodyMedium.copy(fontSize = 13.sp, lineHeight = 18.sp),
        labelLarge = base.labelLarge.copy(fontSize = 12.sp),
    )
}

private fun pulseShapes() = Shapes(
    extraSmall = RoundedCornerShape(12.dp),
    small = RoundedCornerShape(16.dp),
    medium = RoundedCornerShape(22.dp),
    large = RoundedCornerShape(28.dp),
    extraLarge = RoundedCornerShape(36.dp),
)

private fun ledgerShapes() = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(10.dp),
    large = RoundedCornerShape(12.dp),
    extraLarge = RoundedCornerShape(14.dp),
)
