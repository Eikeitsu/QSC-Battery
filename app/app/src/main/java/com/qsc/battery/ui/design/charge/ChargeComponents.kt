package com.qsc.battery.ui.design.charge

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex

@Composable
fun ChargeThemeProvider(
    colors: ChargeColors,
    content: @Composable () -> Unit,
) {
    CompositionLocalProvider(
        LocalChargeColors provides colors,
        LocalChargeTypography provides chargeTypography(),
        LocalChargeDimens provides ChargeDimens(),
        content = content,
    )
}

@Composable
fun StatusScrim(modifier: Modifier = Modifier) {
    val bg = ChargeTheme.colors.scrimTop
    Box(
        modifier = modifier
            .fillMaxWidth()
            .windowInsetsTopHeight(WindowInsets.statusBars)
            .background(
                Brush.verticalGradient(
                    listOf(bg.copy(alpha = 0.96f), bg.copy(alpha = 0.55f), bg.copy(alpha = 0f)),
                ),
            )
            .zIndex(8f),
    )
}

@Composable
fun ImmersiveBottomBar(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    val bg = ChargeTheme.colors.surface.copy(alpha = 0.94f)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(bg),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(horizontal = 6.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

@Composable
fun ChargeScaffold(
    modifier: Modifier = Modifier,
    snackbarHostState: SnackbarHostState? = null,
    bottomBar: @Composable () -> Unit = {},
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(ChargeTheme.colors.background),
    ) {
        // Soft atmosphere
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(280.dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            ChargeTheme.colors.accent.copy(alpha = 0.10f),
                            Color.Transparent,
                        ),
                        center = Offset(0.5f, 0.15f),
                        radius = 900f,
                    ),
                ),
        )
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                content()
                snackbarHostState?.let {
                    SnackbarHost(
                        hostState = it,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(16.dp)
                            .windowInsetsPadding(WindowInsets.navigationBars),
                    )
                }
            }
            bottomBar()
        }
        StatusScrim(modifier = Modifier.align(Alignment.TopCenter))
    }
}

@Composable
fun ChargePage(
    modifier: Modifier = Modifier,
    includeStatusSpacer: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
            .padding(bottom = ChargeTheme.dimens.sectionGap),
        verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
    ) {
        if (includeStatusSpacer) {
            Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        }
        content()
    }
}

@Composable
fun RowScope.ChargeNavItem(
    selected: Boolean,
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    val accent = ChargeTheme.colors.accent
    val muted = ChargeTheme.colors.muted
    val color by animateColorAsState(
        targetValue = if (selected) accent else muted,
        animationSpec = tween(220),
        label = "navColor",
    )
    val indicator by animateFloatAsState(
        targetValue = if (selected) 1f else 0f,
        animationSpec = tween(220),
        label = "navIndicator",
    )
    Column(
        modifier = Modifier
            .weight(1f)
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .height(3.dp)
                .width(18.dp)
                .clip(CircleShape)
                .background(accent.copy(alpha = indicator)),
        )
        Spacer(modifier = Modifier.height(6.dp))
        androidx.compose.foundation.Image(
            painter = rememberVectorPainter(icon),
            contentDescription = label,
            modifier = Modifier.size(22.dp),
            colorFilter = androidx.compose.ui.graphics.ColorFilter.tint(color),
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = label,
            style = ChargeTheme.typography.caption,
            color = color,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}

@Composable
fun ChargePrimaryButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(ChargeTheme.dimens.primaryButton)
            .clip(shape)
            .background(
                if (enabled) ChargeTheme.colors.accent
                else ChargeTheme.colors.accent.copy(alpha = 0.35f),
            )
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = ChargeTheme.typography.headline,
            color = ChargeTheme.colors.onAccent,
        )
    }
}

@Composable
fun ChargeSecondaryButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(ChargeTheme.dimens.secondaryButton)
            .clip(shape)
            .border(1.dp, ChargeTheme.colors.stroke, shape)
            .background(ChargeTheme.colors.surface)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = ChargeTheme.typography.body,
            color = if (enabled) ChargeTheme.colors.ink else ChargeTheme.colors.muted,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
fun ChargeHero(
    levelText: String,
    percent: Float?,
    statusLine: String,
    subtitle: String,
) {
    val p = (percent ?: 0f).coerceIn(0f, 1f)
    val animated by animateFloatAsState(targetValue = p, animationSpec = tween(700), label = "hero")
    val track = ChargeTheme.colors.stroke
    val progress = ChargeTheme.colors.accent
    val glow = ChargeTheme.colors.accent.copy(alpha = 0.18f)
    val heroSize = ChargeTheme.dimens.heroSize
    val heroStroke = ChargeTheme.dimens.heroStroke
    val display = ChargeTheme.typography.display
    val body = ChargeTheme.typography.body
    val caption = ChargeTheme.typography.caption
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize)) {
            Canvas(modifier = Modifier.size(heroSize)) {
                val stroke = heroStroke.toPx()
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
                    sweepAngle = 360f * animated,
                    useCenter = false,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                    size = arcSize,
                    topLeft = topLeft,
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = levelText, style = display, color = ink)
                Text(text = statusLine, style = body, color = muted)
            }
        }
        Spacer(modifier = Modifier.height(10.dp))
        Text(text = subtitle, style = caption, color = muted, textAlign = TextAlign.Center)
    }
}

@Composable
fun ChargeMetricRow(items: List<Pair<String, String>>) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items.take(3).forEach { (label, value) ->
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
                    .background(ChargeTheme.colors.surface)
                    .border(1.dp, ChargeTheme.colors.stroke, RoundedCornerShape(ChargeTheme.dimens.radiusMd))
                    .padding(14.dp),
            ) {
                Text(text = label, style = ChargeTheme.typography.caption, color = ChargeTheme.colors.muted)
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = value,
                    style = ChargeTheme.typography.headline,
                    color = ChargeTheme.colors.ink,
                )
            }
        }
    }
}

@Composable
fun ChargeSection(
    title: String? = null,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (!title.isNullOrBlank()) {
            Text(
                text = title,
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(ChargeTheme.dimens.radiusLg))
                .background(ChargeTheme.colors.surface)
                .border(1.dp, ChargeTheme.colors.stroke, RoundedCornerShape(ChargeTheme.dimens.radiusLg))
                .padding(vertical = 4.dp),
            content = content,
        )
    }
}

@Composable
fun ChargeListRow(
    title: String,
    summary: String? = null,
    value: String? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (onClick != null) {
                    Modifier.clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() },
                        onClick = onClick,
                    )
                } else {
                    Modifier
                },
            )
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = ChargeTheme.typography.body, color = ChargeTheme.colors.ink, fontWeight = FontWeight.Medium)
            if (!summary.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(3.dp))
                Text(text = summary, style = ChargeTheme.typography.caption, color = ChargeTheme.colors.muted)
            }
        }
        if (!value.isNullOrBlank()) {
            Text(
                text = value,
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
        }
        trailing?.invoke(this)
    }
}

@Composable
fun ChargeToggleRow(
    title: String,
    checked: Boolean,
    summary: String? = null,
    onCheckedChange: (Boolean) -> Unit,
) {
    ChargeListRow(
        title = title,
        summary = summary,
        onClick = { onCheckedChange(!checked) },
        trailing = {
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                colors = SwitchDefaults.colors(
                    checkedTrackColor = ChargeTheme.colors.accent,
                    checkedThumbColor = ChargeTheme.colors.onAccent,
                ),
            )
        },
    )
}

@Composable
fun ChargeBanner(text: String, tone: BannerTone = BannerTone.Info) {
    val bg = when (tone) {
        BannerTone.Info -> ChargeTheme.colors.accent.copy(alpha = 0.10f)
        BannerTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.10f)
        BannerTone.Ok -> ChargeTheme.colors.success.copy(alpha = 0.12f)
    }
    val border = when (tone) {
        BannerTone.Info -> ChargeTheme.colors.accent.copy(alpha = 0.25f)
        BannerTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.28f)
        BannerTone.Ok -> ChargeTheme.colors.success.copy(alpha = 0.28f)
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(bg)
            .border(1.dp, border, RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .padding(16.dp),
    ) {
        Text(text = text, style = ChargeTheme.typography.body, color = ChargeTheme.colors.ink)
    }
}

enum class BannerTone { Info, Warn, Ok }

@Composable
fun ChargeSegmented(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(ChargeTheme.colors.surfaceStrong)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEachIndexed { index, label ->
            val selected = index == selectedIndex
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (selected) ChargeTheme.colors.surface else Color.Transparent)
                    .clickable { onSelect(index) }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = label,
                    style = ChargeTheme.typography.label,
                    color = if (selected) ChargeTheme.colors.ink else ChargeTheme.colors.muted,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}

@Composable
fun ChargeTitleBar(title: String, onBack: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "←",
            style = ChargeTheme.typography.headline,
            color = ChargeTheme.colors.ink,
            modifier = Modifier
                .clip(CircleShape)
                .clickable(onClick = onBack)
                .padding(horizontal = 12.dp, vertical = 8.dp),
        )
        Text(text = title, style = ChargeTheme.typography.title, color = ChargeTheme.colors.ink)
    }
}

@Composable
fun ChargeDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(horizontal = 16.dp),
        color = ChargeTheme.colors.stroke,
    )
}
