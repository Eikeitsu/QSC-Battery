package com.qsc.battery.ui.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.moriafly.salt.ui.Button
import com.moriafly.salt.ui.ButtonType
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text
import com.moriafly.salt.ui.UnstableSaltUiApi

object AppDimens {
    val pageHorizontal = 16.dp
    val pageTop = 8.dp
    val sectionGap = 16.dp
    val heroSize = 200.dp
    val heroStroke = 12.dp
    val primaryButtonHeight = 48.dp
}

/** 顶层状态栏渐变遮罩：滚动内容从下方穿过，系统时间始终可读。 */
@Composable
fun StatusScrim(modifier: Modifier = Modifier) {
    val bg = SaltTheme.colors.background
    Box(
        modifier = modifier
            .fillMaxWidth()
            .windowInsetsTopHeight(WindowInsets.statusBars)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        bg.copy(alpha = 0.96f),
                        bg.copy(alpha = 0.72f),
                        bg.copy(alpha = 0f),
                    ),
                ),
            )
            .zIndex(8f),
    )
}

/**
 * 沉浸底栏：背景延伸进 navigationBars / 小白条；
 * 仅图标行做 insets 垫高。
 */
@Composable
fun ImmersiveBottomBar(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    val bg = SaltTheme.colors.subBackground.copy(alpha = 0.92f)
        .compositeOverSafe(SaltTheme.colors.background)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(bg),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(horizontal = 4.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

private fun Color.compositeOverSafe(background: Color): Color {
    val a = alpha
    if (a >= 1f) return this
    val r = red * a + background.red * (1f - a)
    val g = green * a + background.green * (1f - a)
    val b = blue * a + background.blue * (1f - a)
    return Color(r, g, b, 1f)
}

@Composable
fun AppChrome(
    modifier: Modifier = Modifier,
    bottomBar: @Composable () -> Unit = {},
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(SaltTheme.colors.background),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                content()
            }
            bottomBar()
        }
        StatusScrim(modifier = Modifier.align(Alignment.TopCenter))
    }
}

@Composable
fun AppPage(
    modifier: Modifier = Modifier,
    /** 首行 Spacer 吃掉 statusBars，内容可滚入遮罩下 */
    includeStatusSpacer: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = AppDimens.pageHorizontal)
            .padding(top = AppDimens.pageTop, bottom = AppDimens.sectionGap),
        verticalArrangement = Arrangement.spacedBy(AppDimens.sectionGap),
    ) {
        if (includeStatusSpacer) {
            Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        }
        content()
    }
}

@OptIn(UnstableSaltUiApi::class)
@Composable
fun AppPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Button(
        onClick = onClick,
        text = text,
        enabled = enabled,
        type = ButtonType.Highlight,
        modifier = modifier
            .fillMaxWidth()
            .height(AppDimens.primaryButtonHeight),
    )
}

@OptIn(UnstableSaltUiApi::class)
@Composable
fun AppSecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Button(
        onClick = onClick,
        text = text,
        enabled = enabled,
        type = ButtonType.Sub,
        modifier = modifier
            .fillMaxWidth()
            .height(AppDimens.primaryButtonHeight),
    )
}

@Composable
fun RowScope.AppNavItem(
    selected: Boolean,
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    val color = if (selected) SaltTheme.colors.highlight else SaltTheme.colors.subText
    Column(
        modifier = Modifier
            .weight(1f)
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .background(
                    if (selected) SaltTheme.colors.highlight.copy(alpha = 0.14f) else Color.Transparent,
                    CircleShape,
                )
                .padding(horizontal = 14.dp, vertical = 6.dp),
        ) {
            androidx.compose.foundation.Image(
                painter = rememberVectorPainter(icon),
                contentDescription = label,
                modifier = Modifier.size(22.dp),
                colorFilter = androidx.compose.ui.graphics.ColorFilter.tint(color),
            )
        }
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = label,
            color = color,
            style = SaltTheme.textStyles.sub,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}

@Composable
fun AppHeroBattery(
    levelText: String,
    percent: Float?,
    statusLine: String,
    subtitle: String,
) {
    val track = SaltTheme.colors.stroke
    val progress = SaltTheme.colors.highlight
    val glow = SaltTheme.colors.highlight.copy(alpha = 0.22f)
    val p = (percent ?: 0f).coerceIn(0f, 1f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(AppDimens.heroSize)) {
            Canvas(modifier = Modifier.size(AppDimens.heroSize)) {
                val stroke = AppDimens.heroStroke.toPx()
                drawCircle(brush = Brush.radialGradient(listOf(glow, Color.Transparent)))
                val arcSize = Size(size.minDimension - stroke, size.minDimension - stroke)
                val topLeft = Offset(stroke / 2, stroke / 2)
                drawArc(
                    color = track,
                    startAngle = -90f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                    size = arcSize,
                    topLeft = topLeft,
                )
                drawArc(
                    color = progress,
                    startAngle = -90f,
                    sweepAngle = 360f * p,
                    useCenter = false,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                    size = arcSize,
                    topLeft = topLeft,
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = levelText,
                    style = SaltTheme.textStyles.main,
                    fontWeight = FontWeight.Bold,
                    color = SaltTheme.colors.text,
                )
                Text(
                    text = statusLine,
                    style = SaltTheme.textStyles.sub,
                    color = SaltTheme.colors.subText,
                )
            }
        }
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = subtitle,
            style = SaltTheme.textStyles.sub,
            color = SaltTheme.colors.subText,
        )
    }
}

@Composable
fun AppMetricStrip(items: List<Pair<String, String>>) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items.take(3).forEach { (label, value) ->
            Column(
                modifier = Modifier
                    .weight(1f)
                    .background(SaltTheme.colors.subBackground, RoundedCornerShape(14.dp))
                    .padding(12.dp),
            ) {
                Text(text = label, style = SaltTheme.textStyles.sub, color = SaltTheme.colors.subText)
                Spacer(modifier = Modifier.height(4.dp))
                Text(text = value, style = SaltTheme.textStyles.main, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun VoltPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) = AppPrimaryButton(text, onClick, modifier, enabled)

@Composable
fun VoltPage(
    modifier: Modifier = Modifier,
    applyStatusBars: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) = AppPage(modifier = modifier, includeStatusSpacer = applyStatusBars, content = content)

@Composable
fun VoltHeroBattery(
    levelText: String,
    percent: Float?,
    statusLine: String,
    subtitle: String,
) = AppHeroBattery(levelText, percent, statusLine, subtitle)

@Composable
fun VoltMetricStrip(items: List<Pair<String, String>>) = AppMetricStrip(items)

@Composable
fun VoltBanner(text: String, accent: Color = SaltTheme.colors.highlight) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(accent.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
            .padding(16.dp),
    ) {
        Text(text = text, style = SaltTheme.textStyles.main)
    }
}

@Composable
fun StatusBanner(text: String, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    VoltBanner(text)
}
