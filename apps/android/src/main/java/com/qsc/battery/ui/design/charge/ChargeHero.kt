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
    /** 内核 current_now（µA）；仅充电时驱动液面浪高/快慢。 */
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
            clock = motion.clock,
            currentEnergy = currentEnergy,
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
    clock: Float,
    currentEnergy: Float,
    boltAlpha: Float,
    gravity: GravityDown,
    bubbles: List<BubbleActor>,
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
        // 充电：浪高/碎浪/相位速度随电流；未充电固定轻涟漪，不读电流
        val energy = if (charging) currentEnergy.coerceIn(0f, 1f) else 0f
        val waveAmp = if (charging) {
            (fillW * (0.032f + 0.14f * energy)).coerceIn(3.2f, 18f)
        } else {
            (fillW * 0.026f).coerceIn(1.6f, 3.6f)
        }
        val splash = if (charging) 0.18f + 0.55f * energy else 0.12f
        val phase = if (charging) {
            // clock 为秒：~0.5Hz 起，大电流可到 ~2.3Hz
            clock * (PI.toFloat() * 2f) * (0.5f + 1.8f * energy)
        } else {
            wave * (PI.toFloat() * 2f)
        }
        val nx = gravity.nx
        val ny = gravity.ny.coerceAtLeast(0.22f)
        // 右侧低（nx>0）→ 右侧液面 y 更小 → 液体流向右侧低处
        val slope = (nx / ny).coerceIn(-2.4f, 2.4f)
        // 圆柱断面透视厚度：前后缘在屏上的张开量
        val sectionRy = (fillW * 0.20f).coerceIn(12f, 26f)

        /**
         * 液面高度场 h(x,z)。zNorm∈[-1,1]：-1 后壁、+1 前壁。
         * 波动 = 不同时刻的不规则断面，前后相位错开，不是齐整一刀切。
         */
        fun heightField(x: Float, zNorm: Float): Float {
            val t = ((x - fillLeft) / fillW).coerceIn(0f, 1f)
            val z = zNorm.coerceIn(-1f, 1f)
            val along = sin(t * PI.toFloat() * 2f + phase) * waveAmp +
                sin(t * PI.toFloat() * 3.2f + phase * 1.37f) * waveAmp * 0.45f
            val depth = sin(z * PI.toFloat() + phase * 0.88f) * waveAmp * 0.62f +
                sin(z * PI.toFloat() * 2.15f - phase * 1.1f) * waveAmp * 0.28f * splash
            val diagonal = sin(
                (t * 4.3f + z * 2.4f) * PI.toFloat() + phase * 2.05f,
            ) * waveAmp * (0.22f + 0.38f * splash)
            val chop = sin(
                (t * 6.1f - z * 3.2f) * PI.toFloat() - phase * 2.6f,
            ) * waveAmp * 0.16f * splash
            return along + depth + diagonal + chop
        }

        fun chordFactor(x: Float): Float {
            val u = ((x - fillCx) / (fillW * 0.5f)).coerceIn(-1f, 1f)
            return sqrt((1f - u * u).coerceAtLeast(0f))
        }

        /** 把圆柱内 (x,z) 投到屏幕 y：后缘上、前缘下，再叠高度场。 */
        fun projectY(x: Float, zNorm: Float, intercept: Float): Float {
            val z = zNorm.coerceIn(-1f, 1f)
            val base = intercept + slope * (x - fillCx) + heightField(x, z)
            return base + sectionRy * z * chordFactor(x)
        }

        fun meanDepth(intercept: Float): Float {
            val n = 24
            var sum = 0f
            for (i in 0 until n) {
                val x = fillLeft + fillW * ((i + 0.5f) / n)
                // 用断面中线估体积，避免前后缘抖动扯偏电量
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
                val steps = 48
                val samples = Array(steps + 1) { i ->
                    val x = fillLeft + fillW * (i / steps.toFloat())
                    val mid = surfaceAt(x)
                    val back = backY(x)
                    val front = frontY(x)
                    val wet = mid < fillBottom - 0.75f
                    floatArrayOf(x, mid, back, front, if (wet) 1f else 0f)
                }
                val firstWet = samples.indexOfFirst { it[4] > 0.5f }
                val lastWet = samples.indexOfLast { it[4] > 0.5f }
                if (firstWet >= 0 && lastWet >= firstWet) {
                    val wetL = samples[firstWet][0]
                    val wetR = samples[lastWet][0]

                    // 液柱接到前缘（近处断面），筒壁左右明暗
                    val liquid = Path().apply {
                        moveTo(wetL, fillBottom)
                        lineTo(wetR, fillBottom)
                        for (i in lastWet downTo firstWet) {
                            lineTo(samples[i][0], samples[i][3])
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

                    // 不规则断面：逐条带填充，波峰浅、波谷深，后缘暗、前缘亮
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
                    val ampSafe = waveAmp.coerceAtLeast(1f)
                    for (i in firstWet until lastWet) {
                        val x0 = samples[i][0]
                        val x1 = samples[i + 1][0]
                        val b0 = samples[i][2]
                        val f0 = samples[i][3]
                        val b1 = samples[i + 1][2]
                        val f1 = samples[i + 1][3]
                        val h0 = heightField(x0, 0f)
                        val h1 = heightField(x1, 0f)
                        val crest = (((h0 + h1) * 0.5f) / ampSafe * 0.5f + 0.5f).coerceIn(0f, 1f)
                        val thick = (((f0 - b0) + (f1 - b1)) * 0.5f / sectionRy).coerceIn(0.15f, 1.2f)
                        val tone = crest * 0.65f + (1f - (thick - 0.15f).coerceIn(0f, 1f)) * 0.2f
                        fun lerpTone(t: Float): Color {
                            val u = t.coerceIn(0f, 1f)
                            return Color(
                                red = troughDeep.red + (crestLite.red - troughDeep.red) * u,
                                green = troughDeep.green + (crestLite.green - troughDeep.green) * u,
                                blue = troughDeep.blue + (crestLite.blue - troughDeep.blue) * u,
                                alpha = 0.94f,
                            )
                        }
                        val strip = Path().apply {
                            moveTo(x0, b0)
                            lineTo(x1, b1)
                            lineTo(x1, f1)
                            lineTo(x0, f0)
                            close()
                        }
                        val yTop = min(b0, b1)
                        val yBot = maxOf(f0, f1)
                        drawPath(
                            path = strip,
                            brush = Brush.verticalGradient(
                                colors = listOf(
                                    lerpTone(tone * 0.55f),
                                    lerpTone(tone),
                                    lerpTone((tone * 0.85f + 0.15f).coerceAtMost(1f)),
                                ),
                                startY = yTop,
                                endY = yBot,
                            ),
                        )
                    }

                    // 后缘/前缘轮廓：跟着不规则断面走
                    val backLip = Path().apply {
                        for (i in firstWet..lastWet) {
                            val x = samples[i][0]
                            val y = samples[i][2]
                            if (i == firstWet) moveTo(x, y) else lineTo(x, y)
                        }
                    }
                    drawPath(
                        path = backLip,
                        color = Color.Black.copy(alpha = 0.30f),
                        style = Stroke(width = 1.5f, cap = StrokeCap.Round),
                    )
                    val frontLip = Path().apply {
                        for (i in firstWet..lastWet) {
                            val x = samples[i][0]
                            val y = samples[i][3]
                            if (i == firstWet) moveTo(x, y) else lineTo(x, y)
                        }
                    }
                    drawPath(
                        path = frontLip,
                        color = Color.White.copy(alpha = 0.32f),
                        style = Stroke(width = 1.3f, cap = StrokeCap.Round),
                    )

                    if (charging) {
                        val bandCenter = fillBottom - fillHMax * lvl * rise
                        drawRect(
                            brush = Brush.verticalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    Color.White.copy(alpha = 0.16f),
                                    Color.Transparent,
                                ),
                                startY = bandCenter - 18f,
                                endY = bandCenter + 18f,
                            ),
                            topLeft = Offset(fillLeft, fillTopBound),
                            size = Size(fillW, fillHMax),
                        )
                    }

                    bubbles.forEach { b ->
                        val life = bubbleRiseProgress(clock, b) ?: return@forEach
                        val bx = fillLeft + fillW * b.xFrac +
                            sin(life * PI.toFloat() * 2f * b.swayFreq + b.startAt) * b.sway
                        if (bx < wetL - 2f || bx > wetR + 2f) return@forEach
                        val sy = frontY(bx.coerceIn(wetL, wetR))
                        if (sy >= fillBottom - 1f) return@forEach
                        val travel = (fillBottom - 6f - (sy + 1.5f)).coerceAtLeast(8f)
                        val by = fillBottom - 6f - life * travel
                        val birth = smoothstep(0f, 0.08f, life)
                        val merge = smoothstep(0.86f, 1f, life)
                        val visibility = birth * (1f - merge * 0.95f)
                        if (visibility < 0.015f) return@forEach
                        val cyBubble = by * (1f - merge) + (sy + 0.8f) * merge
                        val baseR = b.size * (0.92f + 0.12f * birth)
                        val rw = baseR * (1f + merge * 2.6f)
                        val rh = baseR * (1f - merge * 0.78f).coerceAtLeast(0.18f)
                        val bodyAlpha = 0.52f * visibility * (1f - merge * 0.4f)
                        drawOval(
                            color = Color.White.copy(alpha = bodyAlpha * 0.42f),
                            topLeft = Offset(bx - rw, cyBubble - rh),
                            size = Size(rw * 2f, rh * 2f),
                        )
                        drawOval(
                            color = Color.White.copy(alpha = bodyAlpha),
                            topLeft = Offset(bx - rw * 0.55f, cyBubble - rh * 0.75f),
                            size = Size(rw * 0.7f, rh * 0.55f),
                        )
                        if (merge > 0.02f) {
                            drawOval(
                                color = Color.White.copy(alpha = 0.30f * merge * birth),
                                topLeft = Offset(bx - rw * 1.2f, sy - rh * 0.4f),
                                size = Size(rw * 2.4f, rh * 0.9f),
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
    /** 单调秒表（秒），供气泡各自错峰生命周期使用。 */
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
    // 3600s 循环近似单调时钟，气泡用绝对时间错峰
    val clock by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 3600f,
        animationSpec = infiniteRepeatable(
            animation = tween(3_600_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "clock",
    )
    return BatteryMotion(rise, glow, bolt, wave, clock)
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
