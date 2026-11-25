package com.qsc.battery.ui.design.charge

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.theme.ChargeHeroStyle
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * 首页电量 Hero。三套样式可在「主题外观」切换：
 * - Battery（默认）：竖电池 + 右侧信息（液体电量）
 * - Pulse：柔光外扩 + 软边粒子
 * - Orbit：弧光流转
 */
@Composable
fun ChargeHero(
    levelText: String,
    percent: Float?,
    statusLine: String,
    subtitle: String,
    charging: Boolean = false,
    style: ChargeHeroStyle = ChargeHeroStyle.Battery,
) {
    val p = (percent ?: 0f).coerceIn(0f, 1f)
    val animated by animateFloatAsState(
        targetValue = p,
        animationSpec = tween(800, easing = FastOutSlowInEasing),
        label = "hero",
    )
    when (style) {
        ChargeHeroStyle.Battery -> {
            ChargeHeroBattery(
                levelText,
                statusLine,
                subtitle,
                charging,
                animated,
            )
        }

        ChargeHeroStyle.Pulse -> {
            ChargeHeroPulse(
                levelText,
                statusLine,
                subtitle,
                charging,
                animated,
            )
        }

        ChargeHeroStyle.Orbit -> {
            ChargeHeroOrbit(
                levelText,
                statusLine,
                subtitle,
                charging,
                animated,
            )
        }
    }
}

// ─── 1. 柔光脉冲 ───────────────────────────────────────────────────

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
    val motion = rememberBatteryMotion()
    val gravity = rememberGravityDown()
    val idleBubbles = remember { randomLiquidBubbles(count = 6, speedMin = 0.22f, speedMax = 0.42f) }
    val chargeBubbles = remember { randomLiquidBubbles(count = 16, speedMin = 0.75f, speedMax = 1.45f) }

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
            rise = if (charging) motion.rise else 0f,
            glow = if (charging) motion.glow else 0.08f,
            wave = motion.wave,
            boltAlpha = if (charging) motion.bolt else 0f,
            gravity = gravity,
            bubbles = if (charging) chargeBubbles else idleBubbles,
            modifier = Modifier
                .width(86.dp)
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
                ChargingChip(progress, boltAlpha = motion.bolt)
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
    rise: Float,
    glow: Float,
    wave: Float,
    boltAlpha: Float,
    gravity: GravityDown,
    bubbles: List<LiquidBubble>,
    modifier: Modifier = Modifier,
) {
    val track = ChargeTheme.colors.stroke
    val ink = ChargeTheme.colors.ink
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val strokeW = (min(w, h) * 0.052f).coerceIn(3.8f, 6.5f)
        val bodyW = w * 0.92f
        val bodyLeft = (w - bodyW) / 2f
        val capH = h * 0.078f
        val neckH = strokeW * 0.85f
        val bodyTop = capH - neckH
        val bodyH = h - bodyTop - h * 0.015f
        val rx = bodyW * 0.20f
        val c = Offset(w / 2f, bodyTop + bodyH / 2f)
        val shell = ink.copy(alpha = 0.55f)
        val shellSoft = track.copy(alpha = 0.95f)

        if (charging) {
            drawCircle(
                brush = Brush.radialGradient(
                    0f to accent.copy(alpha = glow * 0.55f),
                    1f to Color.Transparent,
                    center = c,
                    radius = min(w, h) * 0.78f,
                ),
                radius = min(w, h) * 0.78f,
                center = c,
            )
        }

        // 壳底影
        drawRoundRect(
            color = ink.copy(alpha = 0.10f),
            topLeft = Offset(bodyLeft + 3f, bodyTop + 4f),
            size = Size(bodyW, bodyH),
            cornerRadius = CornerRadius(rx, rx),
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

        // 壳体轻微 3D：左亮右暗 + 顶缘受光
        drawPath(
            path = bodyPath,
            brush = Brush.horizontalGradient(
                colors = listOf(
                    Color.White.copy(alpha = 0.16f),
                    Color.Transparent,
                    ink.copy(alpha = 0.10f),
                ),
                startX = bodyLeft,
                endX = bodyLeft + bodyW,
            ),
        )
        drawPath(
            path = bodyPath,
            brush = Brush.verticalGradient(
                colors = listOf(
                    Color.White.copy(alpha = 0.08f),
                    Color.Transparent,
                    ink.copy(alpha = 0.06f),
                ),
                startY = bodyTop,
                endY = bodyTop + bodyH,
            ),
        )

        drawPath(
            path = bodyPath,
            color = shellSoft,
            style = Stroke(width = strokeW, cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
        val innerInset = strokeW * 0.95f
        val innerRx = (rx - innerInset).coerceAtLeast(rx * 0.35f)
        drawRoundRect(
            brush = Brush.horizontalGradient(
                colors = listOf(
                    Color.White.copy(alpha = 0.34f),
                    Color.White.copy(alpha = 0.08f),
                    Color.Transparent,
                ),
            ),
            topLeft = Offset(bodyLeft + innerInset, bodyTop + innerInset),
            size = Size(bodyW - innerInset * 2f, bodyH - innerInset * 2f),
            cornerRadius = CornerRadius(innerRx, innerRx),
            style = Stroke(width = strokeW * 0.42f),
        )

        val capW = bodyW * 0.42f
        val capLeft = (w - capW) / 2f
        val collarW = bodyW * 0.56f
        val collarLeft = (w - collarW) / 2f
        drawRoundRect(
            brush = Brush.verticalGradient(colors = listOf(shell, shellSoft)),
            topLeft = Offset(collarLeft, bodyTop - neckH * 0.15f),
            size = Size(collarW, neckH * 1.35f),
            cornerRadius = CornerRadius(neckH, neckH),
        )
        drawRoundRect(
            brush = Brush.verticalGradient(
                colors = listOf(ink.copy(alpha = 0.42f), shell, shellSoft),
            ),
            topLeft = Offset(capLeft, 0f),
            size = Size(capW, capH),
            cornerRadius = CornerRadius(capH * 0.55f, capH * 0.55f),
        )
        drawRoundRect(
            color = Color.White.copy(alpha = 0.32f),
            topLeft = Offset(capLeft + capW * 0.18f, capH * 0.12f),
            size = Size(capW * 0.64f, capH * 0.28f),
            cornerRadius = CornerRadius(capH * 0.2f, capH * 0.2f),
        )

        val lvl = level.coerceIn(0f, 1f)
        val gap = (strokeW * 1.15f + 3f).coerceIn(6f, 11f)
        val fillLeft = bodyLeft + gap
        val fillTopBound = bodyTop + gap
        val fillBottom = bodyTop + bodyH - gap
        val fillW = bodyW - gap * 2f
        val fillHMax = fillBottom - fillTopBound
        val fillCx = fillLeft + fillW / 2f
        val fillRx = (rx - gap).coerceAtLeast(rx * 0.35f)
        val fillPath = Path().apply {
            addRoundRect(
                RoundRect(
                    left = fillLeft,
                    top = fillTopBound,
                    right = fillLeft + fillW,
                    bottom = fillBottom,
                    cornerRadius = CornerRadius(fillRx, fillRx),
                ),
            )
        }
        val waveAmp = (fillW * 0.05f).coerceIn(3.2f, 7f) * if (charging) 1.25f else 1f
        val phase = wave * (PI.toFloat() * 2f)
        // 重力方向（屏内 y+ 向下）；倾斜时液体向低侧汇聚，可露出一侧底部
        val nx = gravity.nx
        val ny = gravity.ny.coerceAtLeast(0.22f)
        val slope = (-nx / ny).coerceIn(-2.2f, 2.2f)
        fun waveAt(x: Float): Float {
            val t = ((x - fillLeft) / fillW).coerceIn(0f, 1f)
            return sin(t * PI.toFloat() * 2f + phase) * waveAmp +
                sin(t * PI.toFloat() * 3.15f + phase * 1.35f) * waveAmp * 0.42f
        }
        fun planeSurfaceY(x: Float, intercept: Float): Float =
            intercept + slope * (x - fillCx) + waveAt(x)

        fun meanDepth(intercept: Float): Float {
            val samples = 24
            var sum = 0f
            for (i in 0 until samples) {
                val x = fillLeft + fillW * ((i + 0.5f) / samples)
                val sy = planeSurfaceY(x, intercept)
                sum += when {
                    sy <= fillTopBound -> fillHMax
                    sy >= fillBottom -> 0f
                    else -> fillBottom - sy
                }
            }
            return sum / samples
        }

        val targetDepth = lvl * fillHMax
        var lo = fillTopBound - fillHMax * 1.2f
        var hi = fillBottom + fillHMax * 0.6f
        repeat(16) {
            val mid = (lo + hi) * 0.5f
            if (meanDepth(mid) > targetDepth) lo = mid else hi = mid
        }
        val intercept = (lo + hi) * 0.5f
        fun surfaceAt(x: Float): Float = planeSurfaceY(x, intercept)

        clipPath(bodyPath) {
            drawRect(
                brush = Brush.horizontalGradient(
                    colors = listOf(
                        Color.White.copy(alpha = 0.12f),
                        Color.Transparent,
                    ),
                    startX = bodyLeft,
                    endX = bodyLeft + bodyW * 0.38f,
                ),
                topLeft = Offset(bodyLeft, bodyTop),
                size = Size(bodyW * 0.38f, bodyH),
            )
            for (i in 1..3) {
                val y = fillBottom - fillHMax * (i / 4f)
                drawLine(
                    color = ink.copy(alpha = 0.09f),
                    start = Offset(fillLeft + fillW * 0.08f, y),
                    end = Offset(fillLeft + fillW * 0.92f, y),
                    strokeWidth = 1.5f,
                )
            }
        }

        clipPath(fillPath) {
            if (lvl > 0.01f) {
                val steps = 36
                val samples = Array(steps + 1) { i ->
                    val x = fillLeft + fillW * (i / steps.toFloat())
                    val sy = surfaceAt(x)
                    val wet = sy < fillBottom - 0.75f
                    floatArrayOf(x, sy, if (wet) 1f else 0f)
                }
                val firstWet = samples.indexOfFirst { it[2] > 0.5f }
                val lastWet = samples.indexOfLast { it[2] > 0.5f }
                if (firstWet >= 0 && lastWet >= firstWet) {
                    val liquid = Path().apply {
                        moveTo(samples[firstWet][0], fillBottom)
                        lineTo(samples[lastWet][0], fillBottom)
                        for (i in lastWet downTo firstWet) {
                            val sy = samples[i][1].coerceIn(fillTopBound, fillBottom)
                            lineTo(samples[i][0], sy)
                        }
                        close()
                    }
                    drawPath(
                        path = liquid,
                        brush = Brush.verticalGradient(
                            colors = listOf(
                                accent.copy(alpha = 0.58f),
                                accent.copy(alpha = 0.86f),
                                accent.copy(alpha = 0.98f),
                            ),
                            startY = fillTopBound,
                            endY = fillBottom,
                        ),
                    )
                    drawPath(
                        path = liquid,
                        brush = Brush.horizontalGradient(
                            colors = listOf(
                                Color.White.copy(alpha = 0.16f),
                                Color.Transparent,
                                Color.Black.copy(alpha = 0.16f),
                            ),
                            startX = fillLeft,
                            endX = fillLeft + fillW,
                        ),
                    )

                    // 立体水面顶面：近缘亮、远缘沉入液体，波峰浅 / 波谷深
                    val faceDepth = (fillW * 0.11f).coerceIn(6.5f, 12f)
                    for (i in firstWet until lastWet) {
                        val x0 = samples[i][0]
                        val x1 = samples[i + 1][0]
                        val y0 = samples[i][1].coerceIn(fillTopBound, fillBottom)
                        val y1 = samples[i + 1][1].coerceIn(fillTopBound, fillBottom)
                        val tMid = (((x0 + x1) * 0.5f - fillLeft) / fillW).coerceIn(0f, 1f)
                        val crest = (
                            sin(tMid * PI.toFloat() * 2f + phase) * 0.5f + 0.5f
                            ).coerceIn(0f, 1f)
                        val near = Color.White.copy(alpha = 0.22f + 0.38f * crest)
                        val far = accent.copy(alpha = 0.35f + 0.25f * (1f - crest)).let {
                            Color(
                                red = it.red * 0.55f,
                                green = it.green * 0.62f,
                                blue = it.blue * 0.55f,
                                alpha = 0.55f + 0.2f * (1f - crest),
                            )
                        }
                        val slab = Path().apply {
                            moveTo(x0, y0)
                            lineTo(x1, y1)
                            lineTo(x1, (y1 + faceDepth).coerceAtMost(fillBottom))
                            lineTo(x0, (y0 + faceDepth).coerceAtMost(fillBottom))
                            close()
                        }
                        drawPath(
                            path = slab,
                            brush = Brush.verticalGradient(
                                colors = listOf(near, far),
                                startY = min(y0, y1),
                                endY = min(y0, y1) + faceDepth,
                            ),
                        )
                    }
                    // 近缘高光描边（看得见的「顶面轮廓」）
                    val lip = Path().apply {
                        for (i in firstWet..lastWet) {
                            val x = samples[i][0]
                            val y = samples[i][1].coerceIn(fillTopBound, fillBottom)
                            if (i == firstWet) moveTo(x, y) else lineTo(x, y)
                        }
                    }
                    drawPath(
                        path = lip,
                        color = Color.White.copy(alpha = 0.62f),
                        style = Stroke(width = 2.6f, cap = StrokeCap.Round),
                    )

                    if (charging) {
                        val bandCenter = fillBottom - fillHMax * lvl * rise
                        drawRect(
                            brush = Brush.verticalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    Color.White.copy(alpha = 0.26f),
                                    Color.Transparent,
                                ),
                                startY = bandCenter - 18f,
                                endY = bandCenter + 18f,
                            ),
                            topLeft = Offset(fillLeft, fillTopBound),
                            size = Size(fillW, fillHMax),
                        )
                        drawCircle(
                            brush = Brush.radialGradient(
                                0f to accent.copy(alpha = 0.20f * (glow / 0.22f)),
                                1f to Color.Transparent,
                                center = Offset(fillCx, intercept),
                                radius = fillW * 0.55f,
                            ),
                            radius = fillW * 0.55f,
                            center = Offset(fillCx, intercept),
                        )
                    }

                    bubbles.forEach { b ->
                        val life = ((wave * b.speed + b.phase) % 1f + 1f) % 1f
                        val bx = fillLeft + fillW * b.xFrac +
                            sin(life * PI.toFloat() * 2f + b.phase * 6f) * b.sway
                        if (bx < samples[firstWet][0] - 2f || bx > samples[lastWet][0] + 2f) {
                            return@forEach
                        }
                        val sy = surfaceAt(bx)
                        if (sy >= fillBottom - 1f) return@forEach
                        val travel = (fillBottom - 5f - (sy + 3f)).coerceAtLeast(6f)
                        val by = fillBottom - 5f - life * travel
                        val merge = ((life - 0.72f) / 0.28f).coerceIn(0f, 1f)
                        if (merge >= 1f) {
                            // 并入水面：扁椭圆涟漪后消失
                            drawOval(
                                color = Color.White.copy(alpha = 0.28f * (1f - (merge - 0.85f).coerceIn(0f, 1f))),
                                topLeft = Offset(bx - b.size * 2.2f, sy - 1.2f),
                                size = Size(b.size * 4.4f, b.size * 1.1f),
                            )
                            return@forEach
                        }
                        val r = b.size * (1f + merge * 1.6f)
                        val alpha = (0.55f - merge * 0.45f).coerceAtLeast(0.08f)
                        if (by < sy - 1f && merge < 0.55f) return@forEach
                        val cyBubble = if (merge > 0.55f) sy + r * 0.15f else by
                        drawCircle(
                            color = Color.White.copy(alpha = 0.20f * alpha / 0.55f),
                            radius = r,
                            center = Offset(bx, cyBubble),
                        )
                        drawCircle(
                            color = Color.White.copy(alpha = alpha),
                            radius = r * 0.34f,
                            center = Offset(bx - r * 0.22f, cyBubble - r * 0.26f),
                        )
                        if (merge > 0.55f) {
                            drawOval(
                                color = Color.White.copy(alpha = 0.22f * merge),
                                topLeft = Offset(bx - r * 1.6f, sy - 1f),
                                size = Size(r * 3.2f, r * 0.9f),
                            )
                        }
                    }
                }
            }
        }

        // 充电：壳内黄色大闪电（呼吸透明度）
        if (charging) {
            clipPath(bodyPath) {
                val cx = w / 2f
                val cy = bodyTop + bodyH * 0.48f
                val a = boltAlpha.coerceIn(0.55f, 1f)
                val boltYellow = Color(0xFFFFC107)
                val bolt = Path().apply {
                    moveTo(cx + 5f, cy - 26f)
                    lineTo(cx - 12f, cy + 2f)
                    lineTo(cx - 1.5f, cy + 2f)
                    lineTo(cx - 7f, cy + 28f)
                    lineTo(cx + 12f, cy - 2f)
                    lineTo(cx + 1.5f, cy - 2f)
                    close()
                }
                drawPath(
                    bolt,
                    brush = Brush.radialGradient(
                        0f to boltYellow.copy(alpha = 0.55f * a),
                        1f to Color.Transparent,
                        center = Offset(cx, cy),
                        radius = fillW.coerceAtLeast(24f) * 0.9f,
                    ),
                )
                drawPath(bolt, color = boltYellow.copy(alpha = 0.92f * a))
                drawPath(
                    bolt,
                    color = Color(0xFFFFF59D).copy(alpha = 0.75f * a),
                    style = Stroke(width = 2.4f, join = StrokeJoin.Round),
                )
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

private data class BatteryMotion(
    val rise: Float,
    val glow: Float,
    val bolt: Float,
    val wave: Float,
)

private data class LiquidBubble(
    val xFrac: Float,
    val size: Float,
    val speed: Float,
    val phase: Float,
    val sway: Float,
)

/** 屏内重力向下单位向量（x 右、y 下）。直立约为 (0,1)，倾斜时液体向低侧汇聚。 */
private data class GravityDown(val nx: Float, val ny: Float)

private fun randomLiquidBubbles(
    count: Int,
    speedMin: Float,
    speedMax: Float,
    seed: Int = 42,
): List<LiquidBubble> {
    val rnd = Random(seed)
    return List(count) {
        LiquidBubble(
            xFrac = 0.12f + rnd.nextFloat() * 0.76f,
            size = 1.6f + rnd.nextFloat() * 4.2f,
            speed = speedMin + rnd.nextFloat() * (speedMax - speedMin),
            phase = rnd.nextFloat(),
            sway = 2.2f + rnd.nextFloat() * 5.5f,
        )
    }
}

@Composable
private fun rememberGravityDown(): GravityDown {
    val context = LocalContext.current
    var nx by remember { mutableFloatStateOf(0f) }
    var ny by remember { mutableFloatStateOf(1f) }
    DisposableEffect(context) {
        val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sm?.getDefaultSensor(Sensor.TYPE_GRAVITY)
            ?: sm?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (sm == null || sensor == null) {
            return@DisposableEffect onDispose { }
        }
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val ax = event.values.getOrNull(0) ?: return
                val ay = event.values.getOrNull(1) ?: return
                val len = sqrt(ax * ax + ay * ay).coerceAtLeast(0.15f)
                val tx = (ax / len).coerceIn(-0.95f, 0.95f)
                val ty = (ay / len).coerceIn(0.2f, 1f)
                nx = nx * 0.80f + tx * 0.20f
                ny = ny * 0.80f + ty * 0.20f
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        onDispose { sm.unregisterListener(listener) }
    }
    val len = sqrt(nx * nx + ny * ny).coerceAtLeast(0.001f)
    return GravityDown(nx / len, ny / len)
}

@Composable
private fun rememberBatteryMotion(): BatteryMotion {
    val infinite = rememberInfiniteTransition(label = "batteryMotion")
    val rise by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "rise",
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
    val wave by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2800, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "wave",
    )
    return BatteryMotion(rise, glow, bolt, wave)
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
