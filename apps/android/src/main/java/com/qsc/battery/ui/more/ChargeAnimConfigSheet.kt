package com.qsc.battery.ui.more

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.design.charge.ChargeHero
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.theme.BatteryFillStyle
import com.qsc.battery.ui.theme.BatteryOrientation
import com.qsc.battery.ui.theme.ChargeAnimConfig
import com.qsc.battery.ui.theme.ChargeAnimShape
import com.qsc.battery.ui.theme.RingEffect
import kotlin.math.min

/**
 * 宽度吃满父级、高度不限，再按高度等比缩小。
 * （ChargeHero 含 fillMaxWidth，不能用完全无约束测量，否则宽度无穷、缩放失效。）
 */
@Composable
private fun ScaleToFitBox(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Layout(
        content = content,
        modifier = modifier,
    ) { measurables, constraints ->
        val measurable = measurables.firstOrNull()
            ?: return@Layout layout(constraints.minWidth, constraints.minHeight) {}
        val maxW = constraints.maxWidth
        val maxH = constraints.maxHeight
        // 限宽、不限高：圆环 Box(size=方) 保持正方形，不会被压成椭圆
        val childConstraints = Constraints(
            minWidth = 0,
            maxWidth = if (maxW == Constraints.Infinity) Constraints.Infinity else maxW,
            minHeight = 0,
            maxHeight = Constraints.Infinity,
        )
        val placeable = measurable.measure(childConstraints)
        val scale = when {
            placeable.width <= 0 || placeable.height <= 0 -> 1f
            maxH == Constraints.Infinity -> 1f
            else -> min(1f, maxH.toFloat() / placeable.height.toFloat())
        }
        val outW = when {
            maxW == Constraints.Infinity -> (placeable.width * scale).toInt()
            else -> maxW
        }.coerceAtLeast(constraints.minWidth)
        val outH = when {
            maxH == Constraints.Infinity -> (placeable.height * scale).toInt()
            else -> maxH
        }.coerceAtLeast(constraints.minHeight)
        layout(outW, outH) {
            placeable.placeWithLayer(
                x = ((outW - placeable.width * scale) / 2f).toInt(),
                y = ((outH - placeable.height * scale) / 2f).toInt(),
            ) {
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0f, 0f)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChargeAnimConfigSheet(
    config: ChargeAnimConfig,
    onChange: (ChargeAnimConfig) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val cfg = config.normalized()
    // 最高约 86% 屏高，圆角顶边始终留在状态栏下方（不是故意顶满）
    val maxSheetH = (LocalConfiguration.current.screenHeightDp * 0.86f).dp
    // 内容淡入稍慢，减轻「一下弹出」的生硬感（框架 sheet 弹簧本身不好改时长）
    val contentAlpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        contentAlpha.animateTo(1f, animationSpec = tween(durationMillis = 380))
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = ChargeTheme.colors.surface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        // 只吃导航栏 inset，避免系统把 sheet 往状态栏里顶
        contentWindowInsets = { WindowInsets.navigationBars },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = maxSheetH)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp)
                .alpha(contentAlpha.value),
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

            // 固定预览高度：液体/圆环切换时不再改变 sheet 测量高度，杜绝顶边上爬。
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(248.dp)
                    .clip(RoundedCornerShape(ChargeTheme.dimens.radiusLg))
                    .background(ChargeTheme.colors.surfaceStrong.copy(alpha = 0.45f))
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                // 电池形态本身较矮，直接铺完整 ChargeHero（电量/状态文字在右侧）。
                // 圆环+气泡带高于预览框：限宽测量后按高度等比缩小，避免压成椭圆或裁掉气泡。
                // （切勿 Constraints() 无约束测量：fillMaxWidth + weight 会让右侧文字宽变 0，只剩电池壳。）
                val preview = @Composable {
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
                if (cfg.shape == ChargeAnimShape.Ring) {
                    ScaleToFitBox(modifier = Modifier.fillMaxWidth(), content = preview)
                } else {
                    preview()
                }
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
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(
                if (selected) {
                    ChargeTheme.colors.accent.copy(alpha = 0.12f)
                } else {
                    ChargeTheme.colors.surfaceStrong.copy(alpha = 0.45f)
                },
            )
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd),
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = title,
            style = ChargeTheme.typography.label,
            color = ChargeTheme.colors.ink,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
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
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(
                if (selected) {
                    ChargeTheme.colors.accent.copy(alpha = 0.14f)
                } else {
                    ChargeTheme.colors.surfaceStrong.copy(alpha = 0.4f)
                },
            )
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd),
            )
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            style = ChargeTheme.typography.label,
            color = ChargeTheme.colors.ink,
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
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = ChargeTheme.typography.label,
                color = if (enabled) ChargeTheme.colors.ink else ChargeTheme.colors.muted,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            )
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
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(
                if (selected) {
                    ChargeTheme.colors.accent.copy(alpha = 0.12f)
                } else {
                    ChargeTheme.colors.surfaceStrong.copy(alpha = 0.45f)
                },
            )
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd),
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = title,
            style = ChargeTheme.typography.label,
            color = ChargeTheme.colors.ink,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
        Text(
            text = summary,
            style = ChargeTheme.typography.caption,
            color = ChargeTheme.colors.muted,
        )
    }
}
