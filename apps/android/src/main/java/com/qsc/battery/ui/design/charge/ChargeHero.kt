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
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
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
    /** 内核 current_now（µA）；仅充电时驱动三套 Hero 动效强弱/快慢。 */
    currentUa: String = "",
    style: ChargeHeroStyle = ChargeHeroStyle.Battery,
) {
    val p = (percent ?: 0f).coerceIn(0f, 1f)
    val animated by animateFloatAsState(
        targetValue = p,
        animationSpec = tween(800, easing = FastOutSlowInEasing),
        label = "hero",
    )
    val currentEnergy = remember(currentUa, charging) {
        chargeCurrentEnergy(currentUa, charging)
    }
    when (style) {
        ChargeHeroStyle.Battery -> {
            ChargeHeroBattery(
                levelText,
                statusLine,
                subtitle,
                charging,
                animated,
                currentEnergy,
            )
        }

        ChargeHeroStyle.Pulse -> {
            ChargeHeroPulse(
                levelText,
                statusLine,
                subtitle,
                charging,
                animated,
                currentEnergy,
            )
        }

        ChargeHeroStyle.Orbit -> {
            ChargeHeroOrbit(
                levelText,
                statusLine,
                subtitle,
                charging,
                animated,
                currentEnergy,
            )
        }
    }
}

/**
 * 充电电流强度 0..1。未充电恒为 0。
 * 约 5A 视为满档；读不到电流时给中等默认，避免浪完全静死。
 */
private fun chargeCurrentEnergy(currentUa: String, charging: Boolean): Float {
    if (!charging) return 0f
    val ua = currentUa.toLongOrNull() ?: return 0.4f
    val amps = abs(ua) / 1_000_000f
    return (amps / 5f).coerceIn(0f, 1f)
}

// ─── 1. 柔光脉冲 ───────────────────────────────────────────────────

@Composable
private fun ChargeHeroPulse(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    animated: Float,
    currentEnergy: Float,
) {
    val track = ChargeTheme.colors.stroke
    val progress = ChargeTheme.colors.accent
    val heroSize = ChargeTheme.dimens.heroSize
    val heroStroke = ChargeTheme.dimens.heroStroke
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted
    val energy = if (charging) currentEnergy.coerceIn(0f, 1f) else 0f
    val motion = if (charging) rememberPulseMotion(energy) else null
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
                val expand = 0.28f + 0.42f * energy
                val ringAlpha = 0.12f + 0.14f * energy

                // 中心柔光：无硬边；电流越大半径/亮度越高
                val glowR = ringR * (1.35f + 0.45f * energy)
                drawCircle(
                    brush = Brush.radialGradient(
                        0f to progress.copy(alpha = glowA),
                        0.55f to progress.copy(alpha = glowA * 0.35f),
                        1f to Color.Transparent,
                        center = c,
                        radius = glowR,
                    ),
                    radius = glowR,
                    center = c,
                )

                if (motion != null) {
                    val layers = 2 + (energy * 2.5f).toInt().coerceIn(0, 2)
                    // 软边脉冲：多层半透明填充环模拟虚化，不用硬 Stroke
                    for (i in 0..layers) {
                        val phase = (motion.pulse + i / (layers + 1f)) % 1f
                        val ease = FastOutSlowInEasing.transform(phase)
                        val r = ringR * (1.04f + ease * expand)
                        val a = (1f - ease) * ringAlpha
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
                        val shimmerSpan = 16f + 18f * energy
                        val shimmerA = 0.22f + 0.28f * energy
                        rotate(degrees = -90f + 360f * animated - 6f + motion.shimmer * (8f + 16f * energy)) {
                            drawArc(
                                brush = Brush.sweepGradient(
                                    0f to Color.Transparent,
                                    0.4f to Color.White.copy(alpha = shimmerA),
                                    1f to Color.Transparent,
                                ),
                                startAngle = 0f,
                                sweepAngle = shimmerSpan,
                                useCenter = false,
                                style = Stroke(width = stroke * (0.7f + 0.2f * energy), cap = StrokeCap.Round),
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
                currentEnergy = energy,
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
    currentEnergy: Float,
) {
    val track = ChargeTheme.colors.stroke
    val progress = ChargeTheme.colors.accent
    val heroSize = ChargeTheme.dimens.heroSize
    val heroStroke = ChargeTheme.dimens.heroStroke
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted
    val energy = if (charging) currentEnergy.coerceIn(0f, 1f) else 0f
    val motion = if (charging) rememberOrbitMotion(energy) else null
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
                val glowR = ringR * (1.25f + 0.35f * energy)
                drawCircle(
                    brush = Brush.radialGradient(
                        0f to progress.copy(alpha = glowA),
                        0.6f to progress.copy(alpha = glowA * 0.4f),
                        1f to Color.Transparent,
                        center = c,
                        radius = glowR,
                    ),
                    radius = glowR,
                    center = c,
                )
                // 外圈软呼吸环：电流越大张得越开
                if (motion != null) {
                    val pulseR = ringR * (1.06f + motion.breath * (0.10f + 0.16f * energy))
                    drawCircle(
                        brush = Brush.radialGradient(
                            0.85f to Color.Transparent,
                            0.93f to progress.copy(alpha = 0.10f + 0.12f * energy),
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
                        // 拖尾弧：电流大 → 更长更亮更多层
                        val trails = 3 + (energy * 2.2f).toInt().coerceIn(0, 2)
                        val gap = 12f + 6f * energy
                        val headSweep = 32f + 22f * energy
                        rotate(degrees = motion.spin) {
                            for (i in 0..trails) {
                                val start = -90f - i * gap
                                val sweep = (headSweep - i * (5f + 2f * energy)).coerceAtLeast(10f)
                                val a = (0.88f - i * (0.14f - 0.03f * energy)).coerceAtLeast(0.10f)
                                drawArc(
                                    color = if (i == 0) {
                                        Color.White.copy(alpha = a * motion.bolt)
                                    } else {
                                        progress.copy(alpha = a * (0.45f + 0.25f * energy))
                                    },
                                    startAngle = start,
                                    sweepAngle = sweep,
                                    useCenter = false,
                                    style = Stroke(
                                        width = stroke * (1.1f + 0.2f * energy - i * 0.1f),
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
    currentEnergy: Float,
) {
    val progress = ChargeTheme.colors.accent
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted
    val surface = ChargeTheme.colors.surface
    val surfaceStrong = ChargeTheme.colors.surfaceStrong
    val motion = rememberBatteryMotion()
    val gravity = rememberGravityDown()
    val idleBubbles = remember { randomBubbleActors(charging = false) }
    val chargeBubbles = remember { randomBubbleActors(charging = true) }
    val feedBubbles = remember { randomChargeFeedActors() }

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
            clock = motion.clock,
            currentEnergy = currentEnergy,
            boltAlpha = if (charging) motion.bolt else 0f,
            gravity = gravity,
            bubbles = if (charging) chargeBubbles else idleBubbles,
            feedBubbles = if (charging) feedBubbles else emptyList(),
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
    clock: Float,
    currentEnergy: Float,
    boltAlpha: Float,
    gravity: GravityDown,
    bubbles: List<BubbleActor>,
    feedBubbles: List<BubbleActor> = emptyList(),
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
        // 外壳几何中心：大闪电固定于此
        val c = Offset(w / 2f, bodyTop + bodyH / 2f)
        val boltCx = c.x
        val boltCy = c.y
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
        // 充电：浪高/扭断幅度随电流；相位一律用 clock，避免 Restart 跳变
        val energy = if (charging) currentEnergy.coerceIn(0f, 1f) else 0f
        val waveAmp = if (charging) {
            (fillW * (0.034f + 0.15f * energy)).coerceIn(3.4f, 19f)
        } else {
            (fillW * 0.028f).coerceIn(1.8f, 4.2f)
        }
        val splash = if (charging) 0.22f + 0.58f * energy else 0.16f
        val swayHz = if (charging) 0.42f + 1.55f * energy else 0.32f
        // 连续相位（无限摇晃），不用 0→1 Restart
        val phase = clock * (PI.toFloat() * 2f) * swayHz
        val phaseB = clock * (PI.toFloat() * 2f) * (swayHz * 0.63f) + 1.17f
        // 扭断强度：在「单椭圆」与「双瓣错位」之间连续摇摆
        val twist = sin(phase)
        val twist2 = sin(phaseB)
        val twistAmt = (0.35f + 0.65f * splash) * (0.55f + 0.45f * abs(twist))
        val nx = gravity.nx
        val ny = gravity.ny.coerceAtLeast(0.22f)
        val slope = (nx / ny).coerceIn(-2.4f, 2.4f)
        val sectionRy = (fillW * 0.22f).coerceIn(13f, 28f)
        // 前后缘横向错位：扭矩大时看起来像两个错开的椭圆瓣
        val shearMax = sectionRy * (0.55f + 0.75f * splash)

        fun chordFactor(x: Float): Float {
            val u = ((x - fillCx) / (fillW * 0.5f)).coerceIn(-1f, 1f)
            return sqrt((1f - u * u).coerceAtLeast(0f))
        }

        /**
         * 扭断断面高度场：螺旋/S 形断裂，前后反向抬压，
         * 随 twist 在单瓣椭圆与双瓣错位之间过渡。
         */
        fun heightField(x: Float, zNorm: Float): Float {
            val u = ((x - fillCx) / (fillW * 0.5f)).coerceIn(-1f, 1f)
            val z = zNorm.coerceIn(-1f, 1f)
            val chord = chordFactor(x)
            val ang = atan2(z * chord, u)
            // 螺旋扭断主瓣：角向 S 形
            val helix = sin(ang + twist * PI.toFloat()) * waveAmp * (0.75f + 0.45f * splash)
            val helix2 = sin(ang * 2f - twist2 * PI.toFloat()) * waveAmp * 0.38f
            // 前后反向抬升 → 双椭圆错位感
            val counter = z * twist * waveAmp * (0.9f + 0.5f * splash)
            // 对角剪切脊
            val ridge = u * z * twist2 * waveAmp * 0.7f
            val ripple = sin(u * PI.toFloat() * 2.4f + phase * 0.85f) * waveAmp * 0.28f +
                sin((u + z) * PI.toFloat() * 3.6f - phaseB) * waveAmp * 0.18f * splash
            return (helix + helix2 + counter + ridge + ripple) * (0.7f + 0.3f * twistAmt)
        }

        /** 前后缘 X 向错位（扭断剪切）。 */
        fun rimX(x: Float, zNorm: Float): Float {
            val z = zNorm.coerceIn(-1f, 1f)
            val shear = shearMax * twist * z * (0.55f + 0.45f * chordFactor(x))
            return x + shear
        }

        fun projectY(x: Float, zNorm: Float, intercept: Float): Float {
            val z = zNorm.coerceIn(-1f, 1f)
            val base = intercept + slope * (x - fillCx) + heightField(x, z)
            return base + sectionRy * z * chordFactor(x) * (0.85f + 0.25f * abs(twist))
        }

        fun meanDepth(intercept: Float): Float {
            val n = 24
            var sum = 0f
            for (i in 0 until n) {
                val x = fillLeft + fillW * ((i + 0.5f) / n)
                val sy = projectY(x, 0f, intercept)
                sum += when {
                    sy <= fillTopBound -> fillHMax
                    sy >= fillBottom -> 0f
                    else -> fillBottom - sy
                }
            }
            return sum / n
        }

        val targetDepth = lvl * fillHMax
        var lo = fillTopBound - fillHMax * 1.2f
        var hi = fillBottom + fillHMax * 0.6f
        repeat(16) {
            val mid = (lo + hi) * 0.5f
            if (meanDepth(mid) > targetDepth) lo = mid else hi = mid
        }
        val intercept = (lo + hi) * 0.5f

        fun surfaceAt(x: Float): Float = projectY(x, 0f, intercept)
        fun backY(x: Float): Float = projectY(x, -1f, intercept)
            .coerceIn(fillTopBound, fillBottom - 1f)
        fun frontY(x: Float): Float = projectY(x, 1f, intercept)
            .coerceAtMost(fillBottom)

        fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
            val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
            return t * t * (3f - 2f * t)
        }

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
                val steps = 52
                // x, midY, backY, frontY, backX, frontX, wet
                val samples = Array(steps + 1) { i ->
                    val x = fillLeft + fillW * (i / steps.toFloat())
                    val mid = surfaceAt(x)
                    val back = backY(x)
                    val front = frontY(x)
                    val bx = rimX(x, -1f)
                    val fx = rimX(x, 1f)
                    val wet = mid < fillBottom - 0.75f
                    floatArrayOf(x, mid, back, front, bx, fx, if (wet) 1f else 0f)
                }
                val firstWet = samples.indexOfFirst { it[6] > 0.5f }
                val lastWet = samples.indexOfLast { it[6] > 0.5f }
                if (firstWet >= 0 && lastWet >= firstWet) {
                    val wetL = samples[firstWet][0]
                    val wetR = samples[lastWet][0]

                    // 液柱接到前缘（含横向错位）
                    val liquid = Path().apply {
                        moveTo(wetL, fillBottom)
                        lineTo(wetR, fillBottom)
                        for (i in lastWet downTo firstWet) {
                            lineTo(samples[i][5], samples[i][3])
                        }
                        close()
                    }
                    drawPath(
                        path = liquid,
                        brush = Brush.verticalGradient(
                            colors = listOf(
                                accent.copy(alpha = 0.74f),
                                accent.copy(alpha = 0.88f),
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
                                Color.Black.copy(alpha = 0.18f),
                                Color.White.copy(alpha = 0.08f),
                                Color.Transparent,
                                Color.Black.copy(alpha = 0.20f),
                            ),
                            startX = wetL,
                            endX = wetR,
                        ),
                    )

                    val crestLite = Color(
                        red = (accent.red * 0.55f + 0.45f).coerceAtMost(1f),
                        green = (accent.green * 0.55f + 0.45f).coerceAtMost(1f),
                        blue = (accent.blue * 0.55f + 0.45f).coerceAtMost(1f),
                    )
                    val troughDeep = Color(
                        red = accent.red * 0.38f,
                        green = accent.green * 0.52f,
                        blue = accent.blue * 0.38f,
                    )
                    val ridgeDark = Color(
                        red = accent.red * 0.28f,
                        green = accent.green * 0.40f,
                        blue = accent.blue * 0.28f,
                    )
                    val ampSafe = waveAmp.coerceAtLeast(1f)
                    fun lerpTone(from: Color, to: Color, t: Float, a: Float = 0.94f): Color {
                        val u = t.coerceIn(0f, 1f)
                        return Color(
                            red = from.red + (to.red - from.red) * u,
                            green = from.green + (to.green - from.green) * u,
                            blue = from.blue + (to.blue - from.blue) * u,
                            alpha = a,
                        )
                    }
                    // 扭断断面条带：顶点用错位后的前后缘，形成双瓣/S 形
                    for (i in firstWet until lastWet) {
                        val x0 = samples[i][0]
                        val x1 = samples[i + 1][0]
                        val b0 = samples[i][2]
                        val f0 = samples[i][3]
                        val b1 = samples[i + 1][2]
                        val f1 = samples[i + 1][3]
                        val bx0 = samples[i][4]
                        val fx0 = samples[i][5]
                        val bx1 = samples[i + 1][4]
                        val fx1 = samples[i + 1][5]
                        val h0 = heightField(x0, 0f)
                        val h1 = heightField(x1, 0f)
                        val crest = (((h0 + h1) * 0.5f) / ampSafe * 0.5f + 0.5f).coerceIn(0f, 1f)
                        val skew = (abs(fx0 - bx0) + abs(fx1 - bx1)) * 0.5f / shearMax.coerceAtLeast(1f)
                        val tone = (crest * 0.55f + skew.coerceIn(0f, 1f) * 0.35f).coerceIn(0f, 1f)
                        val strip = Path().apply {
                            moveTo(bx0, b0)
                            lineTo(bx1, b1)
                            lineTo(fx1, f1)
                            lineTo(fx0, f0)
                            close()
                        }
                        val yTop = min(b0, b1)
                        val yBot = maxOf(f0, f1)
                        drawPath(
                            path = strip,
                            brush = Brush.verticalGradient(
                                colors = listOf(
                                    lerpTone(ridgeDark, troughDeep, 0.35f + tone * 0.3f),
                                    lerpTone(troughDeep, crestLite, tone),
                                    lerpTone(troughDeep, crestLite, (tone * 0.75f + 0.25f).coerceAtMost(1f)),
                                ),
                                startY = yTop,
                                endY = yBot,
                            ),
                        )
                    }

                    // 断裂中脊（双瓣交界）
                    if (abs(twist) > 0.2f) {
                        val ridge = Path().apply {
                            for (i in firstWet..lastWet) {
                                val x = samples[i][0]
                                val mx = (samples[i][4] + samples[i][5]) * 0.5f
                                val my = samples[i][1]
                                if (i == firstWet) moveTo(mx, my) else lineTo(mx, my)
                            }
                        }
                        drawPath(
                            path = ridge,
                            color = Color.Black.copy(alpha = 0.16f + 0.18f * abs(twist)),
                            style = Stroke(width = 1.2f + abs(twist), cap = StrokeCap.Round),
                        )
                    }

                    val backLip = Path().apply {
                        for (i in firstWet..lastWet) {
                            if (i == firstWet) {
                                moveTo(samples[i][4], samples[i][2])
                            } else {
                                lineTo(samples[i][4], samples[i][2])
                            }
                        }
                    }
                    drawPath(
                        path = backLip,
                        color = Color.Black.copy(alpha = 0.30f),
                        style = Stroke(width = 1.5f, cap = StrokeCap.Round),
                    )
                    val frontLip = Path().apply {
                        for (i in firstWet..lastWet) {
                            if (i == firstWet) {
                                moveTo(samples[i][5], samples[i][3])
                            } else {
                                lineTo(samples[i][5], samples[i][3])
                            }
                        }
                    }
                    drawPath(
                        path = frontLip,
                        color = Color.White.copy(alpha = 0.30f),
                        style = Stroke(width = 1.25f, cap = StrokeCap.Round),
                    )

                    // 浅液因子：液柱实际高度 / 满液，低电量时涡与气泡整体收敛
                    val surfMid = surfaceAt(fillCx).coerceIn(fillTopBound, fillBottom)
                    val liquidDepthPx = (fillBottom - surfMid).coerceAtLeast(0f)
                    val depthNorm = (liquidDepthPx / fillHMax.coerceAtLeast(1f)).coerceIn(0f, 1f)
                    val shallow = (depthNorm / 0.28f).coerceIn(0f, 1f) // <28% 液深开始变浅

                    if (charging) {
                        val bandCenter = fillBottom - fillHMax * lvl * rise
                        drawRect(
                            brush = Brush.verticalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    Color.White.copy(alpha = 0.16f * (0.35f + 0.65f * shallow)),
                                    Color.Transparent,
                                ),
                                startY = bandCenter - 18f,
                                endY = bandCenter + 18f,
                            ),
                            topLeft = Offset(fillLeft, fillTopBound),
                            size = Size(fillW, fillHMax),
                        )

                        // 漩涡：只画在真实液柱内；过浅改为底心小涡，避免「空壳龙卷风」
                        val vortexTop = surfMid + 1.5f
                        val vortexBot = fillBottom - 2.5f
                        val vortexH = vortexBot - vortexTop
                        if (vortexH >= 14f) {
                            val spin = clock * (PI.toFloat() * 2f) *
                                (0.9f + 2.2f * energy) * (0.7f + 0.3f * shallow)
                            val arms = when {
                                depthNorm < 0.18f -> 1
                                depthNorm < 0.35f -> if (energy > 0.45f) 2 else 1
                                else -> 2 + (energy * 2f).toInt().coerceIn(0, 2)
                            }
                            val baseR = fillW * (0.10f + 0.10f * energy) *
                                (0.35f + 0.65f * shallow) *
                                (0.55f + 0.45f * depthNorm)
                            val segs = if (depthNorm < 0.25f) 12 else 22
                            val armAlpha = (0.08f + 0.12f * energy) * (0.4f + 0.6f * shallow)
                            for (arm in 0 until arms) {
                                val armPath = Path()
                                for (s in 0..segs) {
                                    val t = s / segs.toFloat()
                                    val y = vortexBot - t * vortexH
                                    val taper = (1f - t) * (1f - t * 0.35f)
                                    val r = baseR * taper
                                    val ang = spin + arm * (PI.toFloat() * 2f / arms.coerceAtLeast(1)) +
                                        t * (3.2f + 2f * shallow)
                                    val x = fillCx + cos(ang) * r
                                    if (s == 0) armPath.moveTo(x, y) else armPath.lineTo(x, y)
                                }
                                drawPath(
                                    path = armPath,
                                    color = Color.White.copy(alpha = armAlpha),
                                    style = Stroke(
                                        width = (1.2f + 0.8f * energy) * (0.55f + 0.45f * shallow),
                                        cap = StrokeCap.Round,
                                    ),
                                )
                                drawPath(
                                    path = armPath,
                                    color = accent.copy(alpha = armAlpha * 1.35f),
                                    style = Stroke(width = 0.8f, cap = StrokeCap.Round),
                                )
                            }
                            val coreY = vortexBot - vortexH * (0.18f + 0.12f * shallow)
                            val coreR = baseR * (0.4f + 0.15f * shallow)
                            drawCircle(
                                brush = Brush.radialGradient(
                                    0f to Color.White.copy(alpha = 0.12f + 0.16f * energy * shallow),
                                    0.45f to accent.copy(alpha = 0.10f * shallow),
                                    1f to Color.Transparent,
                                    center = Offset(fillCx, coreY),
                                    radius = coreR,
                                ),
                                radius = coreR,
                                center = Offset(fillCx, coreY),
                            )
                        } else if (vortexH >= 6f && charging) {
                            // 极浅：只保留底心微涡，不拉长龙卷
                            val microR = fillW * 0.08f * (0.5f + 0.5f * energy)
                            val spin = clock * (PI.toFloat() * 2f) * (1.4f + 2f * energy)
                            val micro = Path()
                            for (s in 0..10) {
                                val t = s / 10f
                                val ang = spin + t * 4f
                                val r = microR * (1f - t * 0.7f)
                                val x = fillCx + cos(ang) * r
                                val y = fillBottom - 3f - t * vortexH
                                if (s == 0) micro.moveTo(x, y) else micro.lineTo(x, y)
                            }
                            drawPath(
                                path = micro,
                                color = Color.White.copy(alpha = 0.14f + 0.1f * energy),
                                style = Stroke(width = 1.3f, cap = StrokeCap.Round),
                            )
                        }
                    }

                    // 两侧环境气泡：浅液时降密度、缩行程，避免浅池里挤成一团
                    val ambientBudget = when {
                        depthNorm < 0.12f -> 0.2f
                        depthNorm < 0.22f -> 0.45f
                        depthNorm < 0.35f -> 0.7f
                        else -> 1f
                    }
                    bubbles.forEachIndexed { index, b ->
                        if (index / bubbles.size.toFloat() > ambientBudget) return@forEachIndexed
                        val life = bubbleRiseProgress(clock, b) ?: return@forEachIndexed
                        val bx = fillLeft + fillW * b.xFrac +
                            sin(life * PI.toFloat() * 2f * b.swayFreq + b.startAt) * b.sway *
                            (0.45f + 0.55f * shallow)
                        if (bx < wetL - 2f || bx > wetR + 2f) return@forEachIndexed
                        val clampedX = bx.coerceIn(wetL, wetR)
                        val sy = frontY(clampedX)
                        val sxf = rimX(clampedX, 1f)
                        if (sy >= fillBottom - 1f) return@forEachIndexed
                        val travel = (fillBottom - 6f - (sy + 1.5f)).coerceAtLeast(4f)
                        if (travel < 10f && depthNorm < 0.15f) return@forEachIndexed
                        val by = fillBottom - 6f - life * travel
                        val birth = smoothstep(0f, 0.08f, life)
                        val merge = smoothstep(0.86f, 1f, life)
                        val visibility = birth * (1f - merge * 0.95f) * (0.5f + 0.5f * shallow)
                        if (visibility < 0.015f) return@forEachIndexed
                        val cyBubble = by * (1f - merge) + (sy + 0.8f) * merge
                        val sizeScale = 0.55f + 0.45f * shallow
                        val baseR = b.size * sizeScale * (0.92f + 0.12f * birth)
                        val rw = baseR * (1f + merge * 2.6f)
                        val rh = baseR * (1f - merge * 0.78f).coerceAtLeast(0.18f)
                        val bodyAlpha = 0.52f * visibility * (1f - merge * 0.4f)
                        drawOval(
                            color = Color.White.copy(alpha = bodyAlpha * 0.42f),
                            topLeft = Offset(sxf - rw, cyBubble - rh),
                            size = Size(rw * 2f, rh * 2f),
                        )
                        drawOval(
                            color = Color.White.copy(alpha = bodyAlpha),
                            topLeft = Offset(sxf - rw * 0.55f, cyBubble - rh * 0.75f),
                            size = Size(rw * 0.7f, rh * 0.55f),
                        )
                        if (merge > 0.02f) {
                            val spread = rw * (1.1f + merge * 1.4f)
                            val mergePath = Path().apply {
                                val n = 10
                                for (k in 0..n) {
                                    val px = (clampedX - spread + spread * 2f * k / n)
                                        .coerceIn(wetL, wetR)
                                    val py = frontY(px)
                                    val qx = rimX(px, 1f)
                                    if (k == 0) moveTo(qx, py) else lineTo(qx, py)
                                }
                            }
                            val dx = 3f
                            val yL = frontY((clampedX - dx).coerceIn(wetL, wetR))
                            val yR = frontY((clampedX + dx).coerceIn(wetL, wetR))
                            val tang = (yR - yL) / (2f * dx)
                            val thick = (1.1f + merge * 2.2f) * (1f + abs(tang) * 0.35f)
                            drawPath(
                                path = mergePath,
                                color = Color.White.copy(alpha = 0.38f * merge * birth),
                                style = Stroke(width = thick, cap = StrokeCap.Round),
                            )
                            drawPath(
                                path = mergePath,
                                color = Color.White.copy(alpha = 0.18f * merge * birth),
                                style = Stroke(width = thick * 2.2f, cap = StrokeCap.Round),
                            )
                        }
                    }
                }
            }
        }

        // 充电：中心充能气泡（液内螺旋 → 破水后飞向壳心闪电）+ 固定中心大闪电
        if (charging) {
            clipPath(bodyPath) {
                val a = boltAlpha.coerceIn(0.55f, 1f)
                val boltYellow = Color(0xFFFFC107)
                val surfCenter = if (lvl > 0.01f) {
                    surfaceAt(fillCx).coerceIn(fillTopBound, fillBottom)
                } else {
                    fillBottom
                }
                val liquidBottom = fillBottom - 5f
                val liquidDepthPx = (liquidBottom - surfCenter).coerceAtLeast(0f)
                val depthNorm = (liquidDepthPx / fillHMax.coerceAtLeast(1f)).coerceIn(0f, 1f)
                val shallow = (depthNorm / 0.28f).coerceIn(0f, 1f)
                // 液面到闪电的空中段：低电量时空程更长，高电量闪电可能淹没在液内
                val boltInLiquid = boltCy >= surfCenter - 6f
                val airGap = (surfCenter - boltCy).coerceAtLeast(0f)
                // 极浅液：少冒泡，把戏份交给空中飞向闪电
                val feedBudget = when {
                    depthNorm < 0.08f -> 0.35f
                    depthNorm < 0.18f -> 0.55f
                    depthNorm < 0.30f -> 0.75f
                    else -> 1f
                }

                feedBubbles.forEachIndexed { index, b ->
                    if (index / feedBubbles.size.toFloat().coerceAtLeast(1f) > feedBudget) {
                        return@forEachIndexed
                    }
                    val life = bubbleRiseProgress(clock, b) ?: return@forEachIndexed
                    val birth = smoothstep(0f, 0.06f, life)
                    val absorb = smoothstep(0.88f, 1f, life)
                    val visibility = birth * (1f - absorb)
                    if (visibility < 0.02f) return@forEachIndexed

                    val ang = clock * (2.8f + 3.5f * energy) +
                        life * (5.5f + b.swayFreq * 2f) + b.startAt * 3f
                    val pos: Offset
                    val inAir: Boolean
                    if (boltInLiquid || airGap < 10f) {
                        // 高电量：整段在液内螺旋冲向闪电
                        val u = life
                        val y = liquidBottom + (boltCy - liquidBottom) * u
                        val r = fillW * (0.20f + 0.06f * energy) * (1f - u) *
                            (0.35f + 0.65f * depthNorm.coerceIn(0.15f, 1f))
                        pos = Offset(boltCx + cos(ang) * r, y)
                        inAir = y < surfCenter
                    } else {
                        // 低/中电量：真实液深决定液内占比，浅液几乎马上破水飞向闪电
                        val liquidSpan = liquidDepthPx
                        val totalSpan = (liquidSpan + airGap).coerceAtLeast(1f)
                        val tLiq = if (liquidSpan < 10f) {
                            (0.12f + 0.18f * (liquidSpan / 10f)).coerceIn(0.08f, 0.3f)
                        } else {
                            (liquidSpan / totalSpan).coerceIn(0.18f, 0.68f)
                        }
                        if (life <= tLiq && liquidSpan >= 4f) {
                            val u = life / tLiq
                            val y = liquidBottom + (surfCenter - liquidBottom) * u
                            val r = fillW * (0.10f + 0.08f * energy) *
                                (1f - u * 0.7f) * (0.4f + 0.6f * shallow)
                            pos = Offset(fillCx + cos(ang) * r, y)
                            inAir = false
                        } else {
                            val u = if (liquidSpan < 4f) {
                                life
                            } else {
                                ((life - tLiq) / (1f - tLiq)).coerceIn(0f, 1f)
                            }
                            val ease = u * u * (3f - 2f * u)
                            val y = surfCenter + (boltCy - surfCenter) * ease
                            val r = fillW * (0.06f + 0.06f * shallow) * (1f - ease) *
                                (0.4f + 0.6f * abs(sin(ang)))
                            val x = fillCx + (boltCx - fillCx) * ease + cos(ang) * r
                            pos = Offset(x, y)
                            inAir = true
                            if (u in 0.05f..0.92f) {
                                drawLine(
                                    brush = Brush.linearGradient(
                                        colors = listOf(
                                            Color.White.copy(alpha = 0.0f),
                                            boltYellow.copy(alpha = 0.35f * visibility * (1f - u)),
                                            boltYellow.copy(alpha = 0.55f * visibility * ease),
                                        ),
                                        start = Offset(fillCx, surfCenter),
                                        end = Offset(boltCx, boltCy),
                                    ),
                                    start = pos,
                                    end = Offset(
                                        pos.x + (boltCx - pos.x) * 0.35f,
                                        pos.y + (boltCy - pos.y) * 0.35f,
                                    ),
                                    strokeWidth = 1.2f,
                                )
                            }
                        }
                    }

                    val sizeScale = 0.55f + 0.45f * shallow
                    val baseR = b.size * sizeScale * (0.7f + 0.35f * energy) *
                        (0.85f + 0.2f * birth)
                    val shrink = 1f - absorb * 0.85f
                    val rw = baseR * shrink * if (inAir) 0.85f else 1f
                    val rh = baseR * shrink * if (inAir) 0.75f else 1f
                    val alpha = (if (inAir) 0.62f else 0.48f) * visibility
                    drawOval(
                        color = Color.White.copy(alpha = alpha * 0.4f),
                        topLeft = Offset(pos.x - rw, pos.y - rh),
                        size = Size(rw * 2f, rh * 2f),
                    )
                    drawOval(
                        color = (if (inAir) boltYellow else Color.White)
                            .copy(alpha = alpha),
                        topLeft = Offset(pos.x - rw * 0.5f, pos.y - rh * 0.7f),
                        size = Size(rw * 0.7f, rh * 0.55f),
                    )
                    if (absorb > 0.05f) {
                        drawCircle(
                            brush = Brush.radialGradient(
                                0f to boltYellow.copy(alpha = 0.55f * absorb * birth),
                                1f to Color.Transparent,
                                center = Offset(boltCx, boltCy),
                                radius = 10f + absorb * 16f,
                            ),
                            radius = 10f + absorb * 16f,
                            center = Offset(boltCx, boltCy),
                        )
                    }
                }

                // 低电量：水面中心到闪电的柔光充能束（浅液时略加强，补液内戏份不足）
                if (!boltInLiquid && airGap > 12f && lvl > 0.02f) {
                    val beamA = (0.10f + 0.18f * energy) *
                        (0.45f + 0.55f * a) *
                        (0.75f + 0.45f * (1f - shallow))
                    drawLine(
                        brush = Brush.verticalGradient(
                            colors = listOf(
                                accent.copy(alpha = beamA * 0.35f),
                                boltYellow.copy(alpha = beamA),
                                boltYellow.copy(alpha = beamA * 0.15f),
                            ),
                            startY = surfCenter,
                            endY = boltCy,
                        ),
                        start = Offset(fillCx, surfCenter),
                        end = Offset(boltCx, boltCy),
                        strokeWidth = (2.0f + 2.2f * energy) * (0.7f + 0.5f * (1f - shallow)),
                    )
                }

                val bolt = Path().apply {
                    moveTo(boltCx + 5f, boltCy - 26f)
                    lineTo(boltCx - 12f, boltCy + 2f)
                    lineTo(boltCx - 1.5f, boltCy + 2f)
                    lineTo(boltCx - 7f, boltCy + 28f)
                    lineTo(boltCx + 12f, boltCy - 2f)
                    lineTo(boltCx + 1.5f, boltCy - 2f)
                    close()
                }
                drawPath(
                    bolt,
                    brush = Brush.radialGradient(
                        0f to boltYellow.copy(alpha = 0.55f * a),
                        1f to Color.Transparent,
                        center = Offset(boltCx, boltCy),
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

/** 软边上升粒子：径向渐变圆 + 左右/上下边缘淡出；密度/速度随电流。 */
@Composable
private fun SoftBubbleField(
    accent: Color,
    currentEnergy: Float,
    modifier: Modifier = Modifier,
) {
    val energy = currentEnergy.coerceIn(0f, 1f)
    val infinite = rememberInfiniteTransition(label = "softBubbles")
    val clock by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 3600f,
        animationSpec = infiniteRepeatable(
            animation = tween(3_600_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "bubbleClock",
    )
    val seeds = remember {
        List(16) { i ->
            BubbleSeed(
                xFrac = 0.10f + (i * 0.055f) % 0.80f,
                size = 3.0f + (i % 5) * 1.35f,
                speed = 0.45f + (i % 5) * 0.13f,
                phase = (i * 0.17f) % 1f,
                sway = 7f + (i % 4) * 5f,
            )
        }
    }
    val activeCount = (8 + (energy * 8f).toInt()).coerceIn(8, 16)
    val speedBoost = 0.55f + 1.35f * energy
    val sizeBoost = 0.85f + 0.75f * energy
    val fogA = 0.06f + 0.10f * energy

    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height

        drawRect(
            brush = Brush.verticalGradient(
                0f to Color.Transparent,
                0.55f to accent.copy(alpha = fogA * 0.4f),
                1f to accent.copy(alpha = fogA),
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

        seeds.take(activeCount).forEach { b ->
            val life = ((clock * b.speed * speedBoost * 0.22f) + b.phase) % 1f
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
            val alpha = lifeA * edgeX * edgeY * (0.34f + 0.22f * energy)
            val r = b.size * sizeBoost * (0.75f + life * 0.55f)
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

/** 脉冲相位/光晕/扫光速度与亮度随电流（energy 0..1）。 */
@Composable
private fun rememberPulseMotion(energy: Float): PulseMotion {
    val e = energy.coerceIn(0f, 1f)
    val infinite = rememberInfiniteTransition(label = "pulseMotion")
    val clock by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 3600f,
        animationSpec = infiniteRepeatable(
            animation = tween(3_600_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulseClock",
    )
    val pulseHz = 0.28f + 0.95f * e
    val shimmerHz = 0.22f + 0.85f * e
    val pulse = (clock * pulseHz) % 1f
    val shimmer = (clock * shimmerHz) % 1f
    val glowBase = 0.08f + 0.14f * e
    val glowAlpha = glowBase + 0.05f * (0.5f + 0.5f * sin(clock * PI.toFloat() * 2f * (0.4f + e)))
    return PulseMotion(pulse, glowAlpha, shimmer)
}

private data class OrbitMotion(val spin: Float, val breath: Float, val bolt: Float)

/** 弧光转速/呼吸/闪电闪烁随电流（energy 0..1）。 */
@Composable
private fun rememberOrbitMotion(energy: Float): OrbitMotion {
    val e = energy.coerceIn(0f, 1f)
    val infinite = rememberInfiniteTransition(label = "orbitMotion")
    val clock by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 3600f,
        animationSpec = infiniteRepeatable(
            animation = tween(3_600_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "orbitClock",
    )
    // deg/s：约 90→360
    val spin = (clock * (90f + 270f * e)) % 360f
    val breathHz = 0.35f + 0.9f * e
    val breathMid = 0.14f + 0.16f * e
    val breathAmp = 0.06f + 0.12f * e
    val breath = breathMid + breathAmp * sin(clock * PI.toFloat() * 2f * breathHz)
    val boltHz = 0.5f + 1.4f * e
    val bolt = 0.55f + 0.45f * (0.5f + 0.5f * sin(clock * PI.toFloat() * 2f * boltHz))
    return OrbitMotion(spin, breath, bolt)
}

private data class BatteryMotion(
    val rise: Float,
    val glow: Float,
    val bolt: Float,
    /** 单调秒表（秒），供液面相位与气泡生命周期使用。 */
    val clock: Float,
)

/**
 * 独立气泡演员：各自 rise/gap/start，避免同一波次齐生齐灭。
 * @param riseSec 从底部升到水面的时长
 * @param gapSec 到顶消失后到下次出现的等待（可很长，制造不确定性）
 * @param startAt 相对 clock 的首次出现偏移
 */
private data class BubbleActor(
    val xFrac: Float,
    val size: Float,
    val sway: Float,
    val swayFreq: Float,
    val riseSec: Float,
    val gapSec: Float,
    val startAt: Float,
    /** 每个周期真正冒出的概率 0..1 */
    val spawnChance: Float,
)

/** 屏内重力向下单位向量（x 右、y 下）。直立约为 (0,1)，倾斜时液体向低侧汇聚。 */
private data class GravityDown(val nx: Float, val ny: Float)

/** 上升进度 0..1；空档或本周期未抽中出现则返回 null。 */
private fun bubbleRiseProgress(clock: Float, a: BubbleActor): Float? {
    val t = clock - a.startAt
    if (t < 0f) return null
    val cycle = (a.riseSec + a.gapSec).coerceAtLeast(0.05f)
    val cycleIndex = floor(t / cycle).toInt()
    // 周期内确定性伪随机：到点了也不一定冒泡
    val roll = ((cycleIndex * 1_103_515_245 + a.startAt.toRawBits()) ushr 16) and 0x7fff
    if (roll / 32767f > a.spawnChance) return null
    val m = t % cycle
    if (m > a.riseSec) return null
    return (m / a.riseSec).coerceIn(0f, 1f)
}

private fun randomBubbleActors(
    charging: Boolean,
    seed: Int = if (charging) 91 else 37,
): List<BubbleActor> {
    val rnd = Random(seed)
    val count = if (charging) rnd.nextInt(7, 16) else rnd.nextInt(2, 7)
    return List(count) {
        BubbleActor(
            xFrac = 0.10f + rnd.nextFloat() * 0.80f,
            size = if (charging) {
                3.8f + rnd.nextFloat() * 12.5f
            } else {
                3.2f + rnd.nextFloat() * 10.5f
            },
            sway = 1.4f + rnd.nextFloat() * 7.2f,
            swayFreq = 0.7f + rnd.nextFloat() * 2.4f,
            riseSec = if (charging) {
                1.05f + rnd.nextFloat() * 2.9f
            } else {
                2.1f + rnd.nextFloat() * 4.8f
            },
            gapSec = 0.25f + rnd.nextFloat() * (if (charging) 4.2f else 7.5f),
            startAt = rnd.nextFloat() * 20f,
            spawnChance = if (charging) {
                0.45f + rnd.nextFloat() * 0.50f
            } else {
                0.30f + rnd.nextFloat() * 0.55f
            },
        )
    }
}

/** 充电中心充能气泡：底部中心连续冒出，螺旋上升后汇入闪电。 */
private fun randomChargeFeedActors(seed: Int = 77): List<BubbleActor> {
    val rnd = Random(seed)
    return List(rnd.nextInt(12, 20)) {
        BubbleActor(
            xFrac = 0.44f + rnd.nextFloat() * 0.12f,
            size = 2.4f + rnd.nextFloat() * 8.5f,
            sway = 1.0f + rnd.nextFloat() * 4.5f,
            swayFreq = 1.0f + rnd.nextFloat() * 2.8f,
            riseSec = 1.15f + rnd.nextFloat() * 1.9f,
            gapSec = 0.04f + rnd.nextFloat() * 0.55f,
            startAt = rnd.nextFloat() * 8f,
            spawnChance = 0.78f + rnd.nextFloat() * 0.22f,
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
    // 3600s 循环近似单调时钟：液面相位与气泡共用，避免 Restart 跳变
    val clock by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 3600f,
        animationSpec = infiniteRepeatable(
            animation = tween(3_600_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "clock",
    )
    return BatteryMotion(rise, glow, bolt, clock)
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
