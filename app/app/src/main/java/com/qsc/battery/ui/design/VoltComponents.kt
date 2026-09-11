package com.qsc.battery.ui.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

private val GroupShape = RoundedCornerShape(18.dp)

@Composable
fun VoltScaffold(
    modifier: Modifier = Modifier,
    topBar: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = topBar,
        bottomBar = bottomBar,
        content = content,
    )
}

@Composable
fun VoltTopBar(
    title: String,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Surface(color = MaterialTheme.colorScheme.background.copy(alpha = 0.92f)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 8.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回")
                }
            } else {
                Spacer(Modifier.size(48.dp))
            }
            Text(
                title,
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f),
            )
            actions()
        }
    }
}

@Composable
fun VoltPage(
    modifier: Modifier = Modifier,
    applyStatusBars: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .then(if (applyStatusBars) Modifier.windowInsetsPadding(WindowInsets.statusBars) else Modifier)
            .padding(horizontal = VoltDimens.pageHorizontal, vertical = VoltDimens.pageTop),
        verticalArrangement = Arrangement.spacedBy(VoltDimens.sectionGap),
        content = content,
    )
}

@Composable
fun VoltSectionLabel(text: String) {
    Text(
        text = text.uppercase(),
        modifier = Modifier.padding(start = 8.dp, bottom = 2.dp),
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        fontWeight = FontWeight.SemiBold,
    )
}

@Composable
fun VoltSection(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val border = MaterialTheme.colorScheme.outline.copy(alpha = 0.22f)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.55f), GroupShape)
            .border(1.dp, border, GroupShape)
            .padding(vertical = 4.dp),
        content = content,
    )
}

@Composable
fun VoltListRow(
    title: String,
    summary: String? = null,
    onClick: (() -> Unit)? = null,
    showChevron: Boolean = onClick != null,
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = VoltDimens.itemVertical),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            if (!summary.isNullOrBlank()) {
                Spacer(Modifier.height(3.dp))
                Text(summary, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        trailing?.invoke(this)
        if (showChevron && trailing == null) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun VoltSwitchRow(
    title: String,
    checked: Boolean,
    summary: String? = null,
    onCheckedChange: (Boolean) -> Unit,
) {
    VoltListRow(
        title = title,
        summary = summary,
        onClick = { onCheckedChange(!checked) },
        showChevron = false,
        trailing = {
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                colors = SwitchDefaults.colors(
                    checkedTrackColor = MaterialTheme.colorScheme.primary,
                ),
            )
        },
    )
}

@Composable
fun VoltBanner(text: String, accent: Color = MaterialTheme.colorScheme.tertiary) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(accent.copy(alpha = 0.14f), GroupShape)
            .border(1.dp, accent.copy(alpha = 0.35f), GroupShape)
            .padding(16.dp),
    ) {
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun VoltPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp),
        shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
fun VoltHeroBattery(
    levelText: String,
    percent: Float?,
    statusLine: String,
    subtitle: String,
) {
    val track = MaterialTheme.colorScheme.surfaceVariant
    val progress = MaterialTheme.colorScheme.primary
    val glow = MaterialTheme.colorScheme.primary.copy(alpha = 0.25f)
    val p = (percent ?: 0f).coerceIn(0f, 1f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(VoltDimens.heroSize)) {
            Canvas(modifier = Modifier.size(VoltDimens.heroSize)) {
                val stroke = VoltDimens.heroStroke.toPx()
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
                Text(levelText, style = MaterialTheme.typography.displayLarge, fontWeight = FontWeight.Bold)
                Text(statusLine, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun VoltMetricStrip(items: List<Pair<String, String>>) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items.take(3).forEach { (label, value) ->
            Column(
                modifier = Modifier
                    .weight(1f)
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
                    .padding(12.dp),
            ) {
                Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun VoltChipRow(
    options: List<Pair<String, Boolean>>,
    onSelect: (Int) -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEachIndexed { index, (label, selected) ->
            FilterChip(
                selected = selected,
                onClick = { onSelect(index) },
                label = { Text(label) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                ),
            )
        }
    }
}

@Composable
fun VoltBottomNavHost(
    content: @Composable RowScope.() -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
        tonalElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(horizontal = 8.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

@Composable
fun RowScope.VoltNavItem(
    selected: Boolean,
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    val color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        modifier = Modifier
            .weight(1f)
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .background(
                    if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.14f) else Color.Transparent,
                    CircleShape,
                )
                .padding(horizontal = 14.dp, vertical = 6.dp),
        ) {
            Icon(icon, contentDescription = label, tint = color)
        }
        Spacer(Modifier.height(2.dp))
        Text(label, style = MaterialTheme.typography.labelMedium, color = color, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal)
    }
}

@Composable
fun VoltDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(horizontal = 16.dp),
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
    )
}

/* Aliases for gradual migration */
@Composable
fun PrefSwitch(title: String, checked: Boolean, summary: String? = null, onCheckedChange: (Boolean) -> Unit) =
    VoltSwitchRow(title, checked, summary, onCheckedChange)

@Composable
fun PrefAction(title: String, summary: String? = null, onClick: () -> Unit) =
    VoltListRow(title = title, summary = summary, onClick = onClick)

@Composable
fun SectionLabel(text: String) = VoltSectionLabel(text)

@Composable
fun StatusBanner(text: String, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    VoltBanner(text)
}
