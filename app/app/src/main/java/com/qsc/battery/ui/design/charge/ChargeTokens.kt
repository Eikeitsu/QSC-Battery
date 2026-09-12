package com.qsc.battery.ui.design.charge

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Immutable
data class ChargeColors(
    val background: Color,
    val surface: Color,
    val surfaceStrong: Color,
    val ink: Color,
    val muted: Color,
    val accent: Color,
    val onAccent: Color,
    val danger: Color,
    val success: Color,
    val stroke: Color,
    val scrimTop: Color,
)

@Immutable
data class ChargeTypography(
    val display: TextStyle,
    val title: TextStyle,
    val headline: TextStyle,
    val body: TextStyle,
    val label: TextStyle,
    val caption: TextStyle,
    val mono: TextStyle,
)

@Immutable
data class ChargeDimens(
    val pageHorizontal: Dp = 20.dp,
    val sectionGap: Dp = 18.dp,
    /** 顶栏标题区到底部内容的额外呼吸（顶栏自身也有底距） */
    val topBarContentGap: Dp = 16.dp,
    /** 内容区相对底栏的留白 */
    val bottomBarContentGap: Dp = 10.dp,
    val radiusLg: Dp = 22.dp,
    val radiusMd: Dp = 16.dp,
    val primaryButton: Dp = 52.dp,
    val secondaryButton: Dp = 44.dp,
    val heroSize: Dp = 220.dp,
    val heroStroke: Dp = 11.dp,
)

fun chargeLightColors(accent: Color) = ChargeColors(
    background = Color(0xFFF4F7F5),
    surface = Color(0xFFFFFFFF),
    surfaceStrong = Color(0xFFE8F0EC),
    ink = Color(0xFF12201A),
    muted = Color(0xFF5C6F66),
    accent = accent,
    onAccent = Color.White,
    danger = Color(0xFFB3261E),
    success = Color(0xFF1B7F4A),
    stroke = Color(0x1A12201A),
    scrimTop = Color(0xFFF4F7F5),
)

fun chargeDarkColors(accent: Color, amoled: Boolean) = ChargeColors(
    background = if (amoled) Color.Black else Color(0xFF0E1512),
    surface = if (amoled) Color(0xFF121212) else Color(0xFF17201C),
    surfaceStrong = Color(0xFF1F2B25),
    ink = Color(0xFFE8F0EC),
    muted = Color(0xFF9AADA3),
    accent = accent,
    onAccent = Color.White,
    danger = Color(0xFFFF8A80),
    success = Color(0xFF6FCF97),
    stroke = Color(0x33E8F0EC),
    scrimTop = if (amoled) Color.Black else Color(0xFF0E1512),
)

fun chargeTypography() = ChargeTypography(
    display = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 56.sp,
        lineHeight = 60.sp,
        letterSpacing = (-1).sp,
        fontFeatureSettings = "tnum",
    ),
    title = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
    ),
    headline = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 18.sp,
        lineHeight = 24.sp,
    ),
    body = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 22.sp,
    ),
    label = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 13.sp,
        lineHeight = 18.sp,
    ),
    caption = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    ),
    mono = TextStyle(
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Normal,
        fontSize = 11.sp,
        lineHeight = 15.sp,
    ),
)

val LocalChargeColors = staticCompositionLocalOf { chargeLightColors(Color(0xFF0B6E4F)) }
val LocalChargeTypography = staticCompositionLocalOf { chargeTypography() }
val LocalChargeDimens = staticCompositionLocalOf { ChargeDimens() }

object ChargeTheme {
    val colors: ChargeColors
        @Composable get() = LocalChargeColors.current
    val typography: ChargeTypography
        @Composable get() = LocalChargeTypography.current
    val dimens: ChargeDimens
        @Composable get() = LocalChargeDimens.current
}
