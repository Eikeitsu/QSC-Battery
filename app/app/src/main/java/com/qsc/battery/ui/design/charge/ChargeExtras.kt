package com.qsc.battery.ui.design.charge

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

data class ChargeChip(
    val id: String,
    val label: String,
)

@Composable
fun ChargeTopBar(
    title: String,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    subtitle: String? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    // 用内边距呼吸，不用分割线/渐变白条——避免「线下一截白」
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(ChargeTheme.colors.background)
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
            .padding(top = 12.dp, bottom = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            Icon(
                imageVector = Icons.AutoMirrored.Outlined.ArrowBack,
                contentDescription = "返回",
                tint = ChargeTheme.colors.ink,
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .clickable(onClick = onBack)
                    .padding(8.dp),
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = ChargeTheme.typography.title,
                color = ChargeTheme.colors.ink,
            )
            if (!subtitle.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = subtitle,
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.muted,
                )
            }
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = actions,
        )
    }
}

@Composable
fun ChargeTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    suffix: String? = null,
    singleLine: Boolean = true,
    numeric: Boolean = false,
    minLines: Int = 1,
) {
    val shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd)
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        singleLine = singleLine,
        minLines = minLines,
        label = label?.let { { Text(it) } },
        suffix = if (!suffix.isNullOrBlank()) {
            { Text(suffix, color = ChargeTheme.colors.muted) }
        } else {
            null
        },
        shape = shape,
        keyboardOptions = KeyboardOptions(
            keyboardType = if (numeric) KeyboardType.Number else KeyboardType.Text,
        ),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = ChargeTheme.colors.accent,
            unfocusedBorderColor = ChargeTheme.colors.stroke,
            cursorColor = ChargeTheme.colors.accent,
            focusedTextColor = ChargeTheme.colors.ink,
            unfocusedTextColor = ChargeTheme.colors.ink,
            focusedContainerColor = ChargeTheme.colors.surface,
            unfocusedContainerColor = ChargeTheme.colors.surface,
            focusedLabelColor = ChargeTheme.colors.accent,
            unfocusedLabelColor = ChargeTheme.colors.muted,
        ),
    )
}

@Composable
fun ChargeChipGroup(
    chips: List<ChargeChip>,
    selectedId: String?,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    multiSelect: Boolean = false,
    selectedIds: Set<String> = emptySet(),
    onToggle: ((String) -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        chips.forEach { chip ->
            val selected = if (multiSelect) chip.id in selectedIds else chip.id == selectedId
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(
                        if (selected) ChargeTheme.colors.accent.copy(alpha = 0.14f)
                        else ChargeTheme.colors.surfaceStrong,
                    )
                    .border(
                        width = 1.dp,
                        color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                        shape = RoundedCornerShape(999.dp),
                    )
                    .clickable {
                        if (multiSelect) onToggle?.invoke(chip.id) else onSelect(chip.id)
                    }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            ) {
                Text(
                    text = chip.label,
                    style = ChargeTheme.typography.label,
                    color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.ink,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}

@Composable
fun ChargeChoiceRow(
    title: String,
    chips: List<ChargeChip>,
    selectedId: String?,
    onSelect: (String) -> Unit,
    summary: String? = null,
    customLabel: String = "自定义",
    onCustom: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = title,
            style = ChargeTheme.typography.body,
            color = ChargeTheme.colors.ink,
            fontWeight = FontWeight.Medium,
        )
        if (!summary.isNullOrBlank()) {
            Text(text = summary, style = ChargeTheme.typography.caption, color = ChargeTheme.colors.muted)
        }
        val all = if (onCustom != null) chips + ChargeChip("__custom__", customLabel) else chips
        ChargeChipGroup(
            chips = all,
            selectedId = if (chips.any { it.id == selectedId }) selectedId else if (onCustom != null) "__custom__" else selectedId,
            onSelect = { id ->
                if (id == "__custom__") onCustom?.invoke() else onSelect(id)
            },
        )
    }
}

@Composable
fun ChargeSkeletonBox(
    modifier: Modifier = Modifier,
    height: Dp = 56.dp,
) {
    val transition = rememberInfiniteTransition(label = "skel")
    val alpha by transition.animateFloat(
        initialValue = 0.35f,
        targetValue = 0.75f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "skelAlpha",
    )
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .graphicsLayer { this.alpha = alpha }
            .background(ChargeTheme.colors.surfaceStrong),
    )
}

@Composable
fun ChargeMetricSkeleton() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        repeat(3) {
            ChargeSkeletonBox(modifier = Modifier.weight(1f), height = 72.dp)
        }
    }
}

@Composable
fun ChargeScreen(
    topBar: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        topBar()
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
                .padding(
                    top = ChargeTheme.dimens.topBarContentGap,
                    bottom = ChargeTheme.dimens.sectionGap,
                ),
            verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
            content = content,
        )
    }
}

/** Presets aligned with WebUI. */
object ChargePresets {
    val powerStop = listOf(
        ChargeChip("80", "80%"),
        ChargeChip("85", "85%"),
        ChargeChip("90", "90%"),
        ChargeChip("95", "95%"),
        ChargeChip("100", "100%"),
        ChargeChip("110", "关闭"),
    )
    val powerStart = listOf(
        ChargeChip("70", "70%"),
        ChargeChip("75", "75%"),
        ChargeChip("80", "80%"),
        ChargeChip("85", "85%"),
        ChargeChip("90", "90%"),
        ChargeChip("95", "95%"),
    )
    val tempStop = listOf(
        ChargeChip("45", "45°C"),
        ChargeChip("50", "50°C"),
        ChargeChip("55", "55°C"),
        ChargeChip("60", "60°C"),
    )
    val tempStart = listOf(
        ChargeChip("35", "35°C"),
        ChargeChip("40", "40°C"),
        ChargeChip("45", "45°C"),
        ChargeChip("50", "50°C"),
    )
    val currentA = listOf(
        ChargeChip("2000000", "2A"),
        ChargeChip("3000000", "3A"),
        ChargeChip("5000000", "5A"),
        ChargeChip("6000000", "6A"),
        ChargeChip("8000000", "8A"),
    )
    val wakeLock = listOf(
        ChargeChip("0", "关"),
        ChargeChip("auto", "自动"),
        ChargeChip("1", "开"),
    )
    val nativeImpl = listOf(
        ChargeChip("rust", "Rust 版"),
        ChargeChip("c", "C 版"),
        ChargeChip("off", "关闭"),
    )
    val wireless = listOf(
        ChargeChip("same", "与有线相同"),
        ChargeChip("ignore", "忽略无线"),
    )
    val notifyKinds = listOf(
        ChargeChip("stop", "停充"),
        ChargeChip("resume", "恢复"),
        ChargeChip("fail", "失败"),
    )
    val logLevels = listOf(
        ChargeChip("", "全部"),
        ChargeChip("info", "信息"),
        ChargeChip("warn", "警告"),
        ChargeChip("error", "错误"),
        ChargeChip("debug", "调试"),
    )
}

fun batteryStatusLabel(raw: String): String = when (raw.trim().lowercase()) {
    "charging" -> "充电中"
    "full" -> "已充满"
    "discharging" -> "未充电"
    "not charging", "not_charging" -> "未充电"
    "unknown", "" -> "未知"
    else -> raw.ifBlank { "未知" }
}

fun chargeEventTypeLabel(type: String): String = when (type.uppercase()) {
    "PLUG" -> "插电"
    "UNPLUG" -> "拔线"
    "CHARGE_START" -> "开始充电"
    "CHARGE_STOP" -> "停充"
    "MAINTAIN" -> "维持"
    "HEALTH" -> "健康"
    "THERMAL" -> "温度"
    "WARNING" -> "警告"
    "CUSTOM" -> "自定义"
    else -> type
}

fun isActivelyCharging(statusRaw: String, powered: Boolean, stopped: Boolean): Boolean {
    if (!powered || stopped) return false
    return statusRaw.trim().equals("Charging", ignoreCase = true) ||
        statusRaw.trim() == "充电中"
}
