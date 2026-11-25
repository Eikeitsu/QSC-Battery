package com.qsc.battery.ui.more

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.design.charge.ChargeHero
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.theme.BatteryFillStyle
import com.qsc.battery.ui.theme.BatteryOrientation
import com.qsc.battery.ui.theme.ChargeAnimConfig
import com.qsc.battery.ui.theme.ChargeAnimShape
import com.qsc.battery.ui.theme.RingEffect

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChargeAnimConfigSheet(
    config: ChargeAnimConfig,
    onChange: (ChargeAnimConfig) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val cfg = config.normalized()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = ChargeTheme.colors.surface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = "充电动画",
                style = ChargeTheme.typography.title,
                color = ChargeTheme.colors.ink,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = cfg.summaryLabel(),
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(ChargeTheme.dimens.radiusLg))
                    .background(ChargeTheme.colors.surfaceStrong.copy(alpha = 0.45f))
                    .padding(vertical = 8.dp),
            ) {
                ChargeHero(
                    levelText = "66%",
                    percent = 0.66f,
                    statusLine = "预览 · 充电中",
                    subtitle = "主题设置预览",
                    charging = true,
                    currentUa = "2500000",
                    anim = cfg,
                )
            }

            Text(
                text = "形态",
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                fontWeight = FontWeight.SemiBold,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                ShapeCard(
                    title = "电池",
                    summary = "竖/横壳体 + 填充样式",
                    selected = cfg.shape == ChargeAnimShape.Battery,
                    modifier = Modifier.weight(1f),
                    onClick = {
                        onChange(cfg.copy(shape = ChargeAnimShape.Battery).normalized())
                    },
                )
                ShapeCard(
                    title = "圆环",
                    summary = "进度环与能量特效",
                    selected = cfg.shape == ChargeAnimShape.Ring,
                    modifier = Modifier.weight(1f),
                    onClick = {
                        onChange(cfg.copy(shape = ChargeAnimShape.Ring))
                    },
                )
            }

            if (cfg.shape == ChargeAnimShape.Battery) {
                Text(
                    text = "方向",
                    style = ChargeTheme.typography.label,
                    color = ChargeTheme.colors.accent,
                    fontWeight = FontWeight.SemiBold,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SegmentChip(
                        label = "竖",
                        selected = cfg.batteryOrientation == BatteryOrientation.Vertical,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            onChange(cfg.copy(batteryOrientation = BatteryOrientation.Vertical))
                        },
                    )
                    SegmentChip(
                        label = "横",
                        selected = cfg.batteryOrientation == BatteryOrientation.Horizontal,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            onChange(
                                cfg.copy(batteryOrientation = BatteryOrientation.Horizontal)
                                    .normalized(),
                            )
                        },
                    )
                }

                Text(
                    text = "填充样式",
                    style = ChargeTheme.typography.label,
                    color = ChargeTheme.colors.accent,
                    fontWeight = FontWeight.SemiBold,
                )
                val liquidEnabled = cfg.batteryOrientation == BatteryOrientation.Vertical
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    FillRow(
                        title = "液体",
                        summary = if (liquidEnabled) {
                            "立体水面、重力与充能气泡"
                        } else {
                            "横向不支持液体"
                        },
                        selected = cfg.batteryFill == BatteryFillStyle.Liquid,
                        enabled = liquidEnabled,
                        onClick = {
                            onChange(cfg.copy(batteryFill = BatteryFillStyle.Liquid).normalized())
                        },
                    )
                    FillRow(
                        title = "电量块",
                        summary = "分段色块，低电偏红、高电偏绿",
                        selected = cfg.batteryFill == BatteryFillStyle.Blocks,
                        enabled = true,
                        onClick = {
                            onChange(cfg.copy(batteryFill = BatteryFillStyle.Blocks))
                        },
                    )
                    FillRow(
                        title = "普通填充",
                        summary = "圆角实心进度，充电时扫光",
                        selected = cfg.batteryFill == BatteryFillStyle.Solid,
                        enabled = true,
                        onClick = {
                            onChange(cfg.copy(batteryFill = BatteryFillStyle.Solid))
                        },
                    )
                }
            } else {
                Text(
                    text = "圆环效果",
                    style = ChargeTheme.typography.label,
                    color = ChargeTheme.colors.accent,
                    fontWeight = FontWeight.SemiBold,
                )
                val effects = listOf(
                    RingEffect.SoftPulse to ("柔光脉冲" to "外扩柔光环与上升粒子"),
                    RingEffect.ArcOrbit to ("弧光流转" to "进度环弧光拖尾旋转"),
                    RingEffect.NeonMinimal to ("极简霓虹" to "细环进度 + 中心闪电"),
                    RingEffect.LiquidRise to ("液体上涌" to "环内液面，底部粘团汇入"),
                    RingEffect.Concentric to ("同心科技" to "多层同心环呼吸旋转"),
                    RingEffect.PlasmaWave to ("等离子波" to "环缘波浪线与底缘粒子"),
                )
                effects.chunked(2).forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        row.forEach { (effect, labels) ->
                            val (title, summary) = labels
                            EffectCard(
                                title = title,
                                summary = summary,
                                selected = cfg.ringEffect == effect,
                                modifier = Modifier.weight(1f),
                                onClick = { onChange(cfg.copy(ringEffect = effect)) },
                            )
                        }
                        if (row.size == 1) Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun ShapeCard(
    title: String,
    summary: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Column(
        modifier = modifier
            .height(88.dp)
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(
                if (selected) {
                    ChargeTheme.colors.accent.copy(alpha = 0.12f)
                } else {
                    ChargeTheme.colors.surfaceStrong.copy(alpha = 0.55f)
                },
            )
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd),
            )
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = title,
            style = ChargeTheme.typography.label,
            color = ChargeTheme.colors.ink,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = summary,
            style = ChargeTheme.typography.caption,
            color = ChargeTheme.colors.muted,
        )
    }
}

@Composable
private fun SegmentChip(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .height(40.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(
                if (selected) {
                    ChargeTheme.colors.accent.copy(alpha = 0.14f)
                } else {
                    ChargeTheme.colors.surfaceStrong.copy(alpha = 0.5f)
                },
            )
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                shape = RoundedCornerShape(999.dp),
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            style = ChargeTheme.typography.label,
            color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.ink,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}

@Composable
private fun FillRow(
    title: String,
    summary: String,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(
                when {
                    selected -> ChargeTheme.colors.accent.copy(alpha = 0.12f)
                    !enabled -> ChargeTheme.colors.surfaceStrong.copy(alpha = 0.28f)
                    else -> ChargeTheme.colors.surfaceStrong.copy(alpha = 0.5f)
                },
            )
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = when {
                    selected -> ChargeTheme.colors.accent
                    !enabled -> ChargeTheme.colors.stroke.copy(alpha = 0.4f)
                    else -> ChargeTheme.colors.stroke
                },
                shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd),
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = ChargeTheme.typography.label,
                color = if (enabled) ChargeTheme.colors.ink else ChargeTheme.colors.muted,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = summary,
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )
        }
        if (selected) {
            Text(
                text = "使用中",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.accent,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun EffectCard(
    title: String,
    summary: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Column(
        modifier = modifier
            .height(96.dp)
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(
                if (selected) {
                    ChargeTheme.colors.accent.copy(alpha = 0.12f)
                } else {
                    ChargeTheme.colors.surfaceStrong.copy(alpha = 0.5f)
                },
            )
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd),
            )
            .clickable(onClick = onClick)
            .padding(12.dp),
    ) {
        Text(
            text = title,
            style = ChargeTheme.typography.label,
            color = ChargeTheme.colors.ink,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = summary,
            style = ChargeTheme.typography.caption,
            color = ChargeTheme.colors.muted,
        )
    }
}
