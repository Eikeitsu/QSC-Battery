package com.qsc.battery.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.theme.LocalUiMode
import com.qsc.battery.ui.theme.UiMode
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable

@Composable
fun QscPage(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val pulse = LocalUiMode.current == UiMode.Pulse
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = if (pulse) 20.dp else 16.dp, vertical = if (pulse) 12.dp else 8.dp),
        verticalArrangement = Arrangement.spacedBy(if (pulse) 16.dp else 10.dp),
        content = content,
    )
}

@Composable
fun QscSectionLabel(text: String) {
    val pulse = LocalUiMode.current == UiMode.Pulse
    Text(
        text = text,
        modifier = Modifier.padding(
            horizontal = if (pulse) 8.dp else 4.dp,
            vertical = if (pulse) 4.dp else 2.dp,
        ),
        style = if (pulse) MaterialTheme.typography.titleSmall else MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontWeight = if (pulse) FontWeight.SemiBold else FontWeight.Medium,
    )
}

@Composable
fun QscGroup(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    when (LocalUiMode.current) {
        UiMode.Pulse -> {
            Surface(
                modifier = modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.large,
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                tonalElevation = 1.dp,
            ) {
                Column(modifier = Modifier.padding(vertical = 6.dp), content = content)
            }
        }
        UiMode.Ledger -> {
            Surface(
                modifier = modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.45f),
                tonalElevation = 0.dp,
            ) {
                Column(content = content)
            }
        }
    }
}

@Composable
fun QscRow(
    title: String,
    summary: String? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
    val pulse = LocalUiMode.current == UiMode.Pulse
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = if (pulse) 18.dp else 14.dp, vertical = if (pulse) 14.dp else 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            if (!summary.isNullOrBlank()) {
                Spacer(Modifier.height(2.dp))
                Text(
                    summary,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        trailing?.invoke(this)
    }
}

@Composable
fun QscSwitchRow(
    title: String,
    checked: Boolean,
    summary: String? = null,
    onCheckedChange: (Boolean) -> Unit,
) {
    QscRow(
        title = title,
        summary = summary,
        onClick = { onCheckedChange(!checked) },
        trailing = {
            Switch(checked = checked, onCheckedChange = onCheckedChange)
        },
    )
}

@Composable
fun QscBody(
    spacedBy: Dp = 8.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val pulse = LocalUiMode.current == UiMode.Pulse
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = if (pulse) 18.dp else 14.dp, vertical = if (pulse) 12.dp else 10.dp),
        verticalArrangement = Arrangement.spacedBy(spacedBy),
        content = content,
    )
}

@Composable
fun QscBanner(
    text: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    QscGroup {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
            )
            if (actionLabel != null && onAction != null) {
                TextButton(onClick = onAction) { Text(actionLabel) }
            }
        }
    }
}

@Composable
fun QscHeroBattery(
    levelText: String,
    percent: Float?,
    subtitle: String,
    statusLine: String,
) {
    val pulse = LocalUiMode.current == UiMode.Pulse
    val track = MaterialTheme.colorScheme.surfaceVariant
    val progress = MaterialTheme.colorScheme.primary
    val p = (percent ?: 0f).coerceIn(0f, 1f)

    if (pulse) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(196.dp)) {
                Canvas(modifier = Modifier.size(196.dp)) {
                    val stroke = 14.dp.toPx()
                    drawArc(
                        color = track,
                        startAngle = -90f,
                        sweepAngle = 360f,
                        useCenter = false,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                        size = Size(size.minDimension - stroke, size.minDimension - stroke),
                        topLeft = Offset(stroke / 2, stroke / 2),
                    )
                    drawArc(
                        color = progress,
                        startAngle = -90f,
                        sweepAngle = 360f * p,
                        useCenter = false,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                        size = Size(size.minDimension - stroke, size.minDimension - stroke),
                        topLeft = Offset(stroke / 2, stroke / 2),
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        levelText,
                        style = MaterialTheme.typography.displayLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        statusLine,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    } else {
        QscGroup {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(56.dp)
                        .background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        levelText.removeSuffix("%"),
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(statusLine, style = MaterialTheme.typography.titleMedium)
                    Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
fun QscMetricGrid(items: List<Pair<String, String>>) {
    val pulse = LocalUiMode.current == UiMode.Pulse
    if (pulse) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items.chunked(2).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    row.forEach { (label, value) ->
                        Surface(
                            modifier = Modifier.weight(1f),
                            shape = MaterialTheme.shapes.medium,
                            color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        ) {
                            Column(modifier = Modifier.padding(14.dp)) {
                                Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Spacer(Modifier.height(4.dp))
                                Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                    if (row.size == 1) Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    } else {
        Column(modifier = Modifier.fillMaxWidth()) {
            items.forEachIndexed { index, (label, value) ->
                if (index > 0) {
                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 14.dp),
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f),
                    )
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                    Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

/* ---- Compatibility aliases used across screens ---- */

@Composable
fun PrefCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) = QscGroup(modifier = modifier, content = content)

@Composable
fun PrefBody(
    spacedBy: Dp = 8.dp,
    content: @Composable ColumnScope.() -> Unit,
) = QscBody(spacedBy = spacedBy, content = content)

@Composable
fun PrefSwitch(
    title: String,
    checked: Boolean,
    summary: String? = null,
    onCheckedChange: (Boolean) -> Unit,
) = QscSwitchRow(title, checked, summary, onCheckedChange)

@Composable
fun PrefAction(
    title: String,
    summary: String? = null,
    onClick: () -> Unit,
) = QscRow(title = title, summary = summary, onClick = onClick)

@Composable
fun SectionLabel(text: String) = QscSectionLabel(text)

@Composable
fun StatusBanner(
    text: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) = QscBanner(text, actionLabel, onAction)
