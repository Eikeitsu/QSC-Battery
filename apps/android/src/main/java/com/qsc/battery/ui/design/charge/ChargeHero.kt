package com.qsc.battery.ui.design.charge

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.theme.ChargeHeroStyle
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * 首页电量 Hero。三套样式可在「主题外观」切换：
 * - Pulse（默认）：柔光外扩 + 软边粒子
 * - Orbit：弧光流转（旧转圈升级）
 * - Battery：竖电池 + 右侧信息
 */
@Composable
fun ChargeHero(
    levelText: String,
    percent: Float?,
    statusLine: String,
    subtitle: String,
    charging: Boolean = false,
    style: ChargeHeroStyle = ChargeHeroStyle.Pulse,
) {
    val p = (percent ?: 0f).coerceIn(0f, 1f)
    val animated by animateFloatAsState(
        targetValue = p,
        animationSpec = tween(800, easing = FastOutSlowInEasing),
        label = "hero",
    )
    when (style) {
        ChargeHeroStyle.Pulse -> ChargeHeroPulse(
            levelText, statusLine, subtitle, charging, animated,
        )
        ChargeHeroStyle.Orbit -> ChargeHeroOrbit(
            levelText, statusLine, subtitle, charging, animated,
        )
        ChargeHeroStyle.Battery -> ChargeHeroBattery(
            levelText, statusLine, subtitle, charging, animated,
        )
    }
}

// ─── 1. 柔光脉冲（默认） ───────────────────────────────────────────

@Composable
private fun ChargeHeroPulse(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    animated: Float,
) {
    val track = ChargeTheme.colors.stroke
    val progress = ChargeTheme.colors.accent
    val heroSize = ChargeTheme.dimens.heroSize
    val heroStroke = ChargeTheme.dimens.heroStroke
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted
    val motion = if (charging) rememberPulseMotion() else null
    // 足够外扩余量，避免脉冲环顶部被裁成「缺边」
    val canvasPad = 48.dp

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(heroSize + canvasPad),
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val c = Offset(size.width / 2f, size.height / 2f)
                val ringR = (heroSize.toPx() - heroStroke.toPx()) / 2f
                val glowA = motion?.glowAlpha ?: 0.08f

                // 中心柔光：无硬边
                drawCircle(
                    brush = Brush.radialGradient(
                        0f to progress.copy(alpha = glowA),
                        0.55f to progress.copy(alpha = glowA * 0.35f),
                        1f to Color.Transparent,
                        center = c,
                        radius = ringR * 1.55f,
                    ),
                    radius = ringR * 1.55f,
                    center = c,
                )

                if (motion != null) {
                    // 软边脉冲：多层半透明填充环模拟虚化，不用硬 Stroke
                    for (i in 0..2) {
                        val phase = (motion.pulse + i / 3f) % 1f
                        val ease = FastOutSlowInEasing.transform(phase)
                        val r = ringR * (1.04f + ease * 0.42f)
                        val a = (1f - ease) * 0.16f
                        // 外晕
                        drawCircle(
                            brush = Brush.radialGradient(
                                0.72f to Color.Transparent,
                                0.88f to progress.copy(alpha = a * 0.55f),
                                0.94f to progress.copy(alpha = a),
                                1f to Color.Transparent,
                                center = c,
                                radius = r,
                            ),
                            radius = r,
                            center = c,
                        )
                    }
                }
            }

            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize)) {
                Canvas(modifier = Modifier.size(heroSize)) {
                    val stroke = heroStroke.toPx()
                    val arcSize = Size(size.minDimension - stroke, size.minDimension - stroke)
                    val topLeft = Offset(stroke / 2f, stroke / 2f)
                    drawArc(
                        color = track.copy(alpha = 0.55f),
                        startAngle = -90f,
                        sweepAngle = 360f,
                        useCenter = false,
                        style = Stroke(width = stroke * 0.92f, cap = StrokeCap.Round),
                        size = arcSize,
                        topLeft = topLeft,
                    )
                    drawArc(
                        brush = Brush.sweepGradient(
                            colors = listOf(
                                progress.copy(alpha = 0.75f),
                                progress,
                                progress.copy(alpha = 0.9f),
                                progress,
                            ),
                        ),
                        startAngle = -90f,
                        sweepAngle = 360f * animated,
                        useCenter = false,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                        size = arcSize,
                        topLeft = topLeft,
                    )
                    if (motion != null && animated > 0.02f) {
                        rotate(degrees = -90f + 360f * animated - 6f + motion.shimmer * 10f) {
                            drawArc(
                                brush = Brush.sweepGradient(
                                    0f to Color.Transparent,
                                    0.4f to Color.White.copy(alpha = 0.35f),
                                    1f to Color.Transparent,
                                ),
                                startAngle = 0f,
                                sweepAngle = 22f,
                                useCenter = false,
                                style = Stroke(width = stroke * 0.75f, cap = StrokeCap.Round),
                                size = arcSize,
                                topLeft = topLeft,
                            )
                        }
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(text = levelText, style = ChargeTheme.typography.display, color = ink)
                    Text(text = statusLine, style = ChargeTheme.typography.body, color = muted)
                }
            }
        }

        if (charging) {
            Spacer(modifier = Modifier.height(2.dp))
            ChargingChip(progress)
            Spacer(modifier = Modifier.height(6.dp))
            SoftBubbleField(
                accent = progress,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .padding(horizontal = 12.dp),
            )
        }

        Spacer(modifier = Modifier.height(if (charging) 4.dp else 10.dp))
        Text(
            text = subtitle,
            style = ChargeTheme.typography.caption,
            color = muted,
            textAlign = TextAlign.Center,
        )
    }
}

// ─── 2. 弧光流转（旧转圈升级） ─────────────────────────────────────

@Composable
private fun ChargeHeroOrbit(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    animated: Float,
) {
    val track = ChargeTheme.colors.stroke
    val progress = ChargeTheme.colors.accent
    val heroSize = ChargeTheme.dimens.heroSize
    val heroStroke = ChargeTheme.dimens.heroStroke
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted
    val motion = if (charging) rememberOrbitMotion() else null
    val canvasPad = 28.dp

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(heroSize + canvasPad),
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val c = Offset(size.width / 2f, size.height / 2f)
                val ringR = (heroSize.toPx() - heroStroke.toPx()) / 2f
                val glowA = motion?.breath ?: 0.10f
                drawCircle(
                    brush = Brush.radialGradient(
                        0f to progress.copy(alpha = glowA),
                        0.6f to progress.copy(alpha = glowA * 0.4f),
                        1f to Color.Transparent,
                        center = c,
                        radius = ringR * 1.4f,
                    ),
                    radius = ringR * 1.4f,
                    center = c,
                )
                // 外圈软呼吸环
                if (motion != null) {
                    val pulseR = ringR * (1.08f + motion.breath * 0.12f)
                    drawCircle(
                        brush = Brush.radialGradient(
                            0.85f to Color.Transparent,
                            0.93f to progress.copy(alpha = 0.12f),
                            1f to Color.Transparent,
                            center = c,
                            radius = pulseR,
                        ),
                        radius = pulseR,
                        center = c,
                    )
                }
            }

            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize)) {
                Canvas(modifier = Modifier.size(heroSize)) {
                    val stroke = heroStroke.toPx()
                    val arcSize = Size(size.minDimension - stroke, size.minDimension - stroke)
                    val topLeft = Offset(stroke / 2f, stroke / 2f)
                    drawArc(
                        color = track.copy(alpha = 0.5f),
                        startAngle = -90f,
                        sweepAngle = 360f,
                        useCenter = false,
                        style = Stroke(width = stroke * 0.9f, cap = StrokeCap.Round),
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
                    if (motion != null) {
                        // 拖尾弧：多层渐隐，比旧版单段高光更柔和
                        rotate(degrees = motion.spin) {
                            for (i in 0..3) {
                                val start = -90f - i * 14f
                                val sweep = 38f - i * 6f
                                val a = (0.85f - i * 0.18f).coerceAtLeast(0.12f)
                                drawArc(
                                    color = if (i == 0) {
                                        Color.White.copy(alpha = a * motion.bolt)
                                    } else {
                                        progress.copy(alpha = a * 0.55f)
                                    },
                                    startAngle = start,
                                    sweepAngle = sweep,
                                    useCenter = false,
                                    style = Stroke(
                                        width = stroke * (1.15f - i * 0.12f),
                                        cap = StrokeCap.Round,
                                    ),
                                    size = arcSize,
                                    topLeft = topLeft,
                                )
                            }
                        }
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(text = levelText, style = ChargeTheme.typography.display, color = ink)
                    Text(text = statusLine, style = ChargeTheme.typography.body, color = muted)
                    if (charging) {
                        Spacer(modifier = Modifier.height(8.dp))
                        ChargingChip(progress, boltAlpha = motion?.bolt ?: 1f)
                    }
                }
            }
        }
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = subtitle,
            style = ChargeTheme.typography.caption,
            color = muted,
            textAlign = TextAlign.Center,
        )
    }
}

// ─── 3. 竖电池 + 右侧信息 ─────────────────────────────────────────

@Composable
private fun ChargeHeroBattery(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    animated: Float,
) {
    val progress = ChargeTheme.colors.accent
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted
    val surface = ChargeTheme.colors.surface
    val surfaceStrong = ChargeTheme.colors.surfaceStrong
    val motion = if (charging) rememberBatteryMotion() else null

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusLg))
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        surfaceStrong.copy(alpha = 0.55f),
                        surface.copy(alpha = 0.35f),
                        Color.Transparent,
                    ),
                ),
            )
            .padding(horizontal = 18.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        VerticalBatteryGlyph(
            level = animated,
            charging = charging,
            accent = progress,
            shine = motion?.shine ?: 0f,
            glow = motion?.glow ?: 0.1f,
            modifier = Modifier
                .width(72.dp)
                .height(132.dp),
        )

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = levelText,
                style = ChargeTheme.typography.display,
                color = ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = statusLine,
                style = ChargeTheme.typography.body,
                color = muted,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (charging) {
                Spacer(modifier = Modifier.height(4.dp))
                ChargingChip(progress, boltAlpha = motion?.bolt ?: 1f)
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = subtitle,
                style = ChargeTheme.typography.caption,
                color = muted,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun VerticalBatteryGlyph(
    level: Float,
    charging: Boolean,
    accent: Color,
    shine: Float,
    glow: Float,
    modifier: Modifier = Modifier,
) {
    val track = ChargeTheme.colors.stroke
    val ink = ChargeTheme.colors.ink
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val bodyW = w * 0.72f
        val bodyLeft = (w - bodyW) / 2f
        val capH = h * 0.055f
        val bodyTop = capH + h * 0.02f
        val bodyH = h - bodyTop - h * 0.02f
        val rx = bodyW * 0.18f
        val c = Offset(w / 2f, bodyTop + bodyH / 2f)

        // 外晕（仅充电）
        if (charging) {
            drawCircle(
                brush = Brush.radialGradient(
                    0f to accent.copy(alpha = glow * 0.55f),
                    1f to Color.Transparent,
                    center = c,
                    radius = min(w, h) * 0.72f,
                ),
                radius = min(w, h) * 0.72f,
                center = c,
            )
        }

        // 正极帽
        val capW = bodyW * 0.38f
        drawRoundRect(
            color = ink.copy(alpha = 0.35f),
            topLeft = Offset((w - capW) / 2f, 0f),
            size = Size(capW, capH + 2f),
            cornerRadius = CornerRadius(capH, capH),
        )

        val bodyPath = Path().apply {
            addRoundRect(
                RoundRect(
                    left = bodyLeft,
                    top = bodyTop,
                    right = bodyLeft + bodyW,
                    bottom = bodyTop + bodyH,
                    cornerRadius = CornerRadius(rx, rx),
                ),
            )
        }

        // 壳体描边（柔和）
        drawPath(
            path = bodyPath,
            color = track.copy(alpha = 0.7f),
            style = Stroke(width = 2.5f),
        )
        // 壳内浅底
        drawPath(
            path = bodyPath,
            brush = Brush.verticalGradient(
                colors = listOf(
                    Color.White.copy(alpha = 0.04f),
                    Color.Transparent,
                ),
                startY = bodyTop,
                endY = bodyTop + bodyH,
            ),
        )

        val inset = 5f
        val fillMaxH = bodyH - inset * 2f
        val fillH = fillMaxH * level.coerceIn(0f, 1f)
        val fillTop = bodyTop + bodyH - inset - fillH
        clipPath(bodyPath) {
            if (fillH > 0.5f) {
                drawRoundRect(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            accent.copy(alpha = 0.85f),
                            accent,
                        ),
                        startY = fillTop,
                        endY = bodyTop + bodyH - inset,
                    ),
                    topLeft = Offset(bodyLeft + inset, fillTop),
                    size = Size(bodyW - inset * 2f, fillH),
                    cornerRadius = CornerRadius(rx * 0.55f, rx * 0.55f),
                )
                if (charging) {
                    val shineX = bodyLeft + inset + (bodyW - inset * 2f) * shine
                    drawRect(
                        brush = Brush.horizontalGradient(
                            colors = listOf(
                                Color.Transparent,
                                Color.White.copy(alpha = 0.28f),
                                Color.Transparent,
                            ),
                            startX = shineX - 14f,
                            endX = shineX + 14f,
                        ),
                        topLeft = Offset(bodyLeft + inset, fillTop),
                        size = Size(bodyW - inset * 2f, fillH),
                    )
                }
            }
            if (charging) {
                // 闪电
                val cx = w / 2f
                val cy = bodyTop + bodyH * 0.48f
                val bolt = Path().apply {
                    moveTo(cx + 4f, cy - 22f)
                    lineTo(cx - 10f, cy + 2f)
                    lineTo(cx - 1f, cy + 2f)
                    lineTo(cx - 6f, cy + 24f)
                    lineTo(cx + 10f, cy - 2f)
                    lineTo(cx + 1f, cy - 2f)
                    close()
                }
                drawPath(bolt, color = Color.White.copy(alpha = 0.82f))
            }
        }
    }
}

@Composable
private fun ChargingChip(accent: Color, boltAlpha: Float = 1f) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(accent.copy(alpha = 0.12f))
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        Icon(
            imageVector = Icons.Outlined.Bolt,
            contentDescription = null,
            tint = accent.copy(alpha = boltAlpha.coerceIn(0.45f, 1f)),
            modifier = Modifier.size(14.dp),
        )
        Text(
            text = "充电中",
            style = ChargeTheme.typography.caption,
            color = accent,
            fontWeight = FontWeight.Medium,
        )
    }
}

/** 软边上升粒子：径向渐变圆 + 左右/上下边缘淡出，避免与白底硬切。 */
@Composable
private fun SoftBubbleField(
    accent: Color,
    modifier: Modifier = Modifier,
) {
    val infinite = rememberInfiniteTransition(label = "softBubbles")
    val t by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(4800, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "bubbleT",
    )
    val seeds = remember {
        List(10) { i ->
            BubbleSeed(
                xFrac = 0.12f + (i * 0.085f) % 0.76f,
                size = 3.2f + (i % 4) * 1.1f,
                speed = 0.5f + (i % 4) * 0.11f,
                phase = (i * 0.19f) % 1f,
                sway = 8f + (i % 3) * 5f,
            )
        }
    }

    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height

        // 底雾：四周彻底淡出
        drawRect(
            brush = Brush.verticalGradient(
                0f to Color.Transparent,
                0.55f to accent.copy(alpha = 0.04f),
                1f to accent.copy(alpha = 0.10f),
            ),
        )
        drawRect(
            brush = Brush.horizontalGradient(
                0f to Color.Transparent,
                0.18f to Color.White.copy(alpha = 0f),
                0.82f to Color.White.copy(alpha = 0f),
                1f to Color.Transparent,
            ),
        )

        seeds.forEach { b ->
            val life = (t * b.speed + b.phase) % 1f
            val y = h * (1.08f - life * 1.2f)
            val x = w * b.xFrac + sin(life * PI.toFloat() * 2f + b.phase * 5f) * b.sway
            val edgeX = when {
                x < w * 0.12f -> (x / (w * 0.12f)).coerceIn(0f, 1f)
                x > w * 0.88f -> ((w - x) / (w * 0.12f)).coerceIn(0f, 1f)
                else -> 1f
            }
            val edgeY = when {
                y < h * 0.15f -> (y / (h * 0.15f)).coerceIn(0f, 1f)
                y > h * 0.92f -> ((h - y) / (h * 0.08f)).coerceIn(0f, 1f)
                else -> 1f
            }
            val lifeA = when {
                life < 0.1f -> life / 0.1f
                life > 0.7f -> ((1f - life) / 0.3f).coerceIn(0f, 1f)
                else -> 1f
            }
            val alpha = lifeA * edgeX * edgeY * 0.42f
            val r = b.size * (0.75f + life * 0.55f)
            // 软圆：径向渐变，边缘透明
            drawCircle(
                brush = Brush.radialGradient(
                    0f to accent.copy(alpha = alpha),
                    0.55f to accent.copy(alpha = alpha * 0.45f),
                    1f to Color.Transparent,
                    center = Offset(x, y),
                    radius = r,
                ),
                radius = r,
                center = Offset(x, y),
            )
        }
    }
}

// ─── Motion ───────────────────────────────────────────────────────

private data class PulseMotion(val pulse: Float, val glowAlpha: Float, val shimmer: Float)

@Composable
private fun rememberPulseMotion(): PulseMotion {
    val infinite = rememberInfiniteTransition(label = "pulseMotion")
    val pulse by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2600, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulse",
    )
    val glow by infinite.animateFloat(
        initialValue = 0.08f,
        targetValue = 0.18f,
        animationSpec = infiniteRepeatable(
            animation = tween(1800, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glow",
    )
    val shimmer by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(3000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "shimmer",
    )
    return PulseMotion(pulse, glow, shimmer)
}

private data class OrbitMotion(val spin: Float, val breath: Float, val bolt: Float)

@Composable
private fun rememberOrbitMotion(): OrbitMotion {
    val infinite = rememberInfiniteTransition(label = "orbitMotion")
    val spin by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(2400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "spin",
    )
    val breath by infinite.animateFloat(
        initialValue = 0.14f,
        targetValue = 0.32f,
        animationSpec = infiniteRepeatable(
            animation = tween(1600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "breath",
    )
    val bolt by infinite.animateFloat(
        initialValue = 0.55f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "bolt",
    )
    return OrbitMotion(spin, breath, bolt)
}

private data class BatteryMotion(val shine: Float, val glow: Float, val bolt: Float)

@Composable
private fun rememberBatteryMotion(): BatteryMotion {
    val infinite = rememberInfiniteTransition(label = "batteryMotion")
    val shine by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "shine",
    )
    val glow by infinite.animateFloat(
        initialValue = 0.10f,
        targetValue = 0.22f,
        animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glow",
    )
    val bolt by infinite.animateFloat(
        initialValue = 0.6f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "bolt",
    )
    return BatteryMotion(shine, glow, bolt)
}

private data class BubbleSeed(
    val xFrac: Float,
    val size: Float,
    val speed: Float,
    val phase: Float,
    val sway: Float,
)

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
