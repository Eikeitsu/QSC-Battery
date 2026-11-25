package com.qsc.battery.ui.design.charge

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

// ─── 电池：电量块 / 普通填充 ─────────────────────────────────────

@Composable
internal fun ChargeHeroBatteryBlocks(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    level: Float,
    currentEnergy: Float,
    horizontal: Boolean,
) {
    BatteryInfoRow(
        levelText = levelText,
        statusLine = statusLine,
        subtitle = subtitle,
        charging = charging,
        currentEnergy = currentEnergy,
        glyphWidth = if (horizontal) 120.dp else 86.dp,
        glyphHeight = if (horizontal) 56.dp else 132.dp,
    ) { accent, ink, track ->
        BatteryBlocksCanvas(
            level = level,
            charging = charging,
            energy = currentEnergy,
            horizontal = horizontal,
            accent = accent,
            ink = ink,
            track = track,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
internal fun ChargeHeroBatterySolid(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    level: Float,
    currentEnergy: Float,
    horizontal: Boolean,
) {
    BatteryInfoRow(
        levelText = levelText,
        statusLine = statusLine,
        subtitle = subtitle,
        charging = charging,
        currentEnergy = currentEnergy,
        glyphWidth = if (horizontal) 120.dp else 86.dp,
        glyphHeight = if (horizontal) 56.dp else 132.dp,
    ) { accent, ink, track ->
        BatterySolidCanvas(
            level = level,
            charging = charging,
            energy = currentEnergy,
            horizontal = horizontal,
            accent = accent,
            ink = ink,
            track = track,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun BatteryInfoRow(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    currentEnergy: Float,
    glyphWidth: Dp,
    glyphHeight: Dp,
    glyph: @Composable (accent: Color, ink: Color, track: Color) -> Unit,
) {
    val accent = ChargeTheme.colors.accent
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted
    val surface = ChargeTheme.colors.surface
    val surfaceStrong = ChargeTheme.colors.surfaceStrong
    val track = ChargeTheme.colors.stroke
    val boltAlpha = if (charging) 0.65f + 0.35f * currentEnergy else 1f

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
        Box(modifier = Modifier.width(glyphWidth).height(glyphHeight)) {
            glyph(accent, ink, track)
        }
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
                ChargingChip(accent, boltAlpha = boltAlpha)
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
private fun BatteryBlocksCanvas(
    level: Float,
    charging: Boolean,
    energy: Float,
    horizontal: Boolean,
    accent: Color,
    ink: Color,
    track: Color,
    modifier: Modifier = Modifier,
) {
    val infinite = rememberInfiniteTransition(label = "blocks")
    val pulse by infinite.animateFloat(
        initialValue = 0.85f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween((900 - 400 * energy).toInt().coerceIn(400, 900), easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "blockPulse",
    )
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val stroke = (min(w, h) * 0.055f).coerceIn(3.5f, 6f)
        if (horizontal) {
            val bodyH = h * 0.72f
            val bodyTop = (h - bodyH) / 2f
            val capW = w * 0.07f
            val bodyW = w - capW - stroke
            drawRoundRect(
                color = ink.copy(alpha = 0.55f),
                topLeft = Offset(stroke / 2f, bodyTop),
                size = Size(bodyW, bodyH),
                cornerRadius = CornerRadius(bodyH * 0.22f),
                style = Stroke(width = stroke),
            )
            drawRoundRect(
                color = track.copy(alpha = 0.9f),
                topLeft = Offset(bodyW + stroke * 0.2f, bodyTop + bodyH * 0.28f),
                size = Size(capW, bodyH * 0.44f),
                cornerRadius = CornerRadius(capW * 0.35f),
            )
            val pad = stroke * 1.4f
            val innerL = stroke / 2f + pad
            val innerT = bodyTop + pad
            val innerW = bodyW - pad * 2f
            val innerH = bodyH - pad * 2f
            val segments = 5
            val gap = 4f
            val segW = (innerW - gap * (segments - 1)) / segments
            val lit = (level.coerceIn(0f, 1f) * segments).toInt().coerceIn(0, segments)
            val partial = (level.coerceIn(0f, 1f) * segments) - lit
            for (i in 0 until segments) {
                val x = innerL + i * (segW + gap)
                val fill = when {
                    i < lit -> 1f
                    i == lit -> partial
                    else -> 0f
                }
                if (fill <= 0.02f) continue
                val t = (i + 0.5f) / segments
                val col = blockColor(t, accent).copy(
                    alpha = if (charging && i == lit.coerceAtMost(segments - 1)) {
                        0.75f + 0.25f * pulse
                    } else {
                        0.95f
                    },
                )
                drawRoundRect(
                    color = col,
                    topLeft = Offset(x, innerT),
                    size = Size(segW * fill.coerceAtLeast(0.08f), innerH),
                    cornerRadius = CornerRadius(4f),
                )
            }
        } else {
            val bodyW = w * 0.88f
            val bodyLeft = (w - bodyW) / 2f
            val capH = h * 0.08f
            val bodyTop = capH * 0.7f
            val bodyH = h - bodyTop - h * 0.02f
            drawRoundRect(
                color = ink.copy(alpha = 0.5f),
                topLeft = Offset((w - bodyW * 0.4f) / 2f, 0f),
                size = Size(bodyW * 0.4f, capH),
                cornerRadius = CornerRadius(capH * 0.4f),
            )
            drawRoundRect(
                color = ink.copy(alpha = 0.55f),
                topLeft = Offset(bodyLeft, bodyTop),
                size = Size(bodyW, bodyH),
                cornerRadius = CornerRadius(bodyW * 0.18f),
                style = Stroke(width = stroke),
            )
            val pad = stroke * 1.35f
            val innerL = bodyLeft + pad
            val innerT = bodyTop + pad
            val innerW = bodyW - pad * 2f
            val innerH = bodyH - pad * 2f
            val segments = 5
            val gap = 5f
            val segH = (innerH - gap * (segments - 1)) / segments
            val lit = (level.coerceIn(0f, 1f) * segments).toInt().coerceIn(0, segments)
            val partial = (level.coerceIn(0f, 1f) * segments) - lit
            for (i in 0 until segments) {
                val fromBottom = i
                val y = innerT + innerH - (fromBottom + 1) * segH - fromBottom * gap
                val fill = when {
                    fromBottom < lit -> 1f
                    fromBottom == lit -> partial
                    else -> 0f
                }
                if (fill <= 0.02f) continue
                val t = (fromBottom + 0.5f) / segments
                val col = blockColor(t, accent).copy(
                    alpha = if (charging && fromBottom == lit.coerceAtMost(segments - 1)) {
                        0.75f + 0.25f * pulse
                    } else {
                        0.95f
                    },
                )
                val hSeg = segH * fill.coerceAtLeast(0.1f)
                drawRoundRect(
                    color = col,
                    topLeft = Offset(innerL, y + (segH - hSeg)),
                    size = Size(innerW, hSeg),
                    cornerRadius = CornerRadius(5f),
                )
            }
        }
    }
}

private fun blockColor(t: Float, accent: Color): Color {
    val red = Color(0xFFE53935)
    val orange = Color(0xFFFB8C00)
    val yellow = Color(0xFFFDD835)
    return when {
        t < 0.25f -> lerpColor(red, orange, t / 0.25f)
        t < 0.5f -> lerpColor(orange, yellow, (t - 0.25f) / 0.25f)
        t < 0.75f -> lerpColor(yellow, accent, (t - 0.5f) / 0.25f)
        else -> accent
    }
}

private fun lerpColor(a: Color, b: Color, t: Float): Color {
    val u = t.coerceIn(0f, 1f)
    return Color(
        red = a.red + (b.red - a.red) * u,
        green = a.green + (b.green - a.green) * u,
        blue = a.blue + (b.blue - a.blue) * u,
        alpha = 1f,
    )
}

@Composable
private fun BatterySolidCanvas(
    level: Float,
    charging: Boolean,
    energy: Float,
    horizontal: Boolean,
    accent: Color,
    ink: Color,
    track: Color,
    modifier: Modifier = Modifier,
) {
    val infinite = rememberInfiniteTransition(label = "solid")
    val shimmer by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween((2200 - 900 * energy).toInt().coerceIn(900, 2200), easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "solidShimmer",
    )
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val stroke = (min(w, h) * 0.055f).coerceIn(3.5f, 6f)
        val lvl = level.coerceIn(0f, 1f)
        if (horizontal) {
            val bodyH = h * 0.72f
            val bodyTop = (h - bodyH) / 2f
            val capW = w * 0.07f
            val bodyW = w - capW - stroke
            drawRoundRect(
                color = ink.copy(alpha = 0.55f),
                topLeft = Offset(stroke / 2f, bodyTop),
                size = Size(bodyW, bodyH),
                cornerRadius = CornerRadius(bodyH * 0.22f),
                style = Stroke(width = stroke),
            )
            drawRoundRect(
                color = track.copy(alpha = 0.9f),
                topLeft = Offset(bodyW + stroke * 0.2f, bodyTop + bodyH * 0.28f),
                size = Size(capW, bodyH * 0.44f),
                cornerRadius = CornerRadius(capW * 0.35f),
            )
            val pad = stroke * 1.35f
            val innerL = stroke / 2f + pad
            val innerT = bodyTop + pad
            val innerW = (bodyW - pad * 2f) * lvl
            val innerH = bodyH - pad * 2f
            if (innerW > 1f) {
                drawRoundRect(
                    brush = Brush.horizontalGradient(
                        colors = listOf(accent.copy(alpha = 0.75f), accent),
                    ),
                    topLeft = Offset(innerL, innerT),
                    size = Size(innerW, innerH),
                    cornerRadius = CornerRadius(6f),
                )
                if (charging) {
                    val sx = innerL + innerW * shimmer
                    drawRect(
                        brush = Brush.horizontalGradient(
                            colors = listOf(
                                Color.Transparent,
                                Color.White.copy(alpha = 0.28f),
                                Color.Transparent,
                            ),
                        ),
                        topLeft = Offset(sx - 12f, innerT),
                        size = Size(24f, innerH),
                    )
                }
            }
        } else {
            val bodyW = w * 0.88f
            val bodyLeft = (w - bodyW) / 2f
            val capH = h * 0.08f
            val bodyTop = capH * 0.7f
            val bodyH = h - bodyTop - h * 0.02f
            drawRoundRect(
                color = ink.copy(alpha = 0.5f),
                topLeft = Offset((w - bodyW * 0.4f) / 2f, 0f),
                size = Size(bodyW * 0.4f, capH),
                cornerRadius = CornerRadius(capH * 0.4f),
            )
            drawRoundRect(
                color = ink.copy(alpha = 0.55f),
                topLeft = Offset(bodyLeft, bodyTop),
                size = Size(bodyW, bodyH),
                cornerRadius = CornerRadius(bodyW * 0.18f),
                style = Stroke(width = stroke),
            )
            val pad = stroke * 1.35f
            val innerL = bodyLeft + pad
            val innerW = bodyW - pad * 2f
            val innerHMax = bodyH - pad * 2f
            val fillH = innerHMax * lvl
            val innerT = bodyTop + pad + (innerHMax - fillH)
            if (fillH > 1f) {
                drawRoundRect(
                    brush = Brush.verticalGradient(
                        colors = listOf(accent.copy(alpha = 0.7f), accent),
                    ),
                    topLeft = Offset(innerL, innerT),
                    size = Size(innerW, fillH),
                    cornerRadius = CornerRadius(6f),
                )
                if (charging) {
                    val sy = innerT + fillH * (1f - shimmer)
                    drawRect(
                        brush = Brush.verticalGradient(
                            colors = listOf(
                                Color.Transparent,
                                Color.White.copy(alpha = 0.28f),
                                Color.Transparent,
                            ),
                        ),
                        topLeft = Offset(innerL, sy - 10f),
                        size = Size(innerW, 20f),
                    )
                }
            }
        }
    }
}

// ─── 圆环变体 ────────────────────────────────────────────────────

@Composable
internal fun ChargeHeroRingNeon(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    level: Float,
    currentEnergy: Float,
) {
    RingHeroScaffold(subtitle, charging, currentEnergy) { accent, ink, muted, energy ->
        val infinite = rememberInfiniteTransition(label = "neon")
        val breath by infinite.animateFloat(
            initialValue = 0.55f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween((1200 - 500 * energy).toInt().coerceIn(500, 1200), FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "neonBreath",
        )
        val heroSize = ChargeTheme.dimens.heroSize
        val heroStroke = ChargeTheme.dimens.heroStroke
        val track = ChargeTheme.colors.stroke
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize)) {
            Canvas(modifier = Modifier.size(heroSize)) {
                val stroke = heroStroke.toPx() * 0.85f
                val arcSize = Size(size.minDimension - stroke, size.minDimension - stroke)
                val topLeft = Offset(stroke / 2f, stroke / 2f)
                val c = Offset(size.width / 2f, size.height / 2f)
                if (charging) {
                    drawCircle(
                        brush = Brush.radialGradient(
                            0f to accent.copy(alpha = 0.12f * breath * (0.5f + 0.5f * energy)),
                            1f to Color.Transparent,
                            center = c,
                            radius = size.minDimension * 0.55f,
                        ),
                        radius = size.minDimension * 0.55f,
                        center = c,
                    )
                }
                drawArc(
                    color = track.copy(alpha = 0.45f),
                    startAngle = -90f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = stroke * 0.7f, cap = StrokeCap.Round),
                    size = arcSize,
                    topLeft = topLeft,
                )
                drawArc(
                    color = accent.copy(alpha = 0.55f + 0.45f * if (charging) breath else 1f),
                    startAngle = -90f,
                    sweepAngle = 360f * level,
                    useCenter = false,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                    size = arcSize,
                    topLeft = topLeft,
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = levelText, style = ChargeTheme.typography.display, color = ink)
                if (charging) {
                    Icon(
                        imageVector = Icons.Outlined.Bolt,
                        contentDescription = null,
                        tint = Color(0xFFFFC107).copy(alpha = 0.55f + 0.45f * breath),
                        modifier = Modifier.size(22.dp),
                    )
                }
                Text(text = statusLine, style = ChargeTheme.typography.body, color = muted)
            }
        }
    }
}

@Composable
internal fun ChargeHeroRingLiquidRise(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    level: Float,
    currentEnergy: Float,
) {
    RingHeroScaffold(subtitle, charging, currentEnergy) { accent, ink, muted, energy ->
        val infinite = rememberInfiniteTransition(label = "liqRise")
        val clock by infinite.animateFloat(
            initialValue = 0f,
            targetValue = 3600f,
            animationSpec = infiniteRepeatable(
                animation = tween(3_600_000, easing = LinearEasing),
                repeatMode = RepeatMode.Restart,
            ),
            label = "liqClock",
        )
        val seeds = remember {
            List(8) { i ->
                floatArrayOf(
                    0.15f + (i * 0.1f) % 0.7f,
                    4f + (i % 4) * 2.2f,
                    0.4f + (i % 5) * 0.12f,
                    (i * 0.17f) % 1f,
                )
            }
        }
        val heroSize = ChargeTheme.dimens.heroSize
        val heroStroke = ChargeTheme.dimens.heroStroke
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize + 40.dp)) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val c = Offset(size.width / 2f, size.height / 2f - 8f)
                    val ringR = (heroSize.toPx() - heroStroke.toPx()) / 2f
                    val stroke = heroStroke.toPx()
                    // 环内液面
                    val fillY = c.y + ringR - 2f * ringR * level
                    drawCircle(
                        color = accent.copy(alpha = 0.12f),
                        radius = ringR,
                        center = c,
                    )
                    if (level > 0.02f) {
                        val liquid = Path().apply {
                            val steps = 36
                            for (i in 0..steps) {
                                val ang = PI.toFloat() * (i / steps.toFloat())
                                val x = c.x - ringR * cos(ang)
                                val yBase = c.y + ringR * sin(ang)
                                val wave = sin(ang * 3f + clock * (1.2f + energy)) * (3f + 4f * energy)
                                val y = yBase.coerceAtLeast(fillY + wave)
                                if (i == 0) moveTo(x, y) else lineTo(x, y)
                            }
                            lineTo(c.x + ringR, c.y + ringR)
                            lineTo(c.x - ringR, c.y + ringR)
                            close()
                        }
                        drawPath(liquid, color = accent.copy(alpha = 0.55f))
                    }
                    drawCircle(
                        color = accent.copy(alpha = 0.9f),
                        radius = ringR,
                        center = c,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                    )
                    if (charging) {
                        val speed = 0.35f + 0.9f * energy
                        seeds.forEach { s ->
                            val life = ((clock * s[2] * speed) + s[3]) % 1f
                            val y = size.height * (0.92f - life * 0.55f)
                            val x = size.width * s[0] + sin(life * 6f + s[3]) * 10f
                            val r = s[1] * (0.7f + life * 0.6f) * (0.7f + 0.4f * energy)
                            val a = when {
                                life < 0.1f -> life / 0.1f
                                life > 0.75f -> ((1f - life) / 0.25f).coerceIn(0f, 1f)
                                else -> 1f
                            } * 0.45f
                            drawCircle(
                                brush = Brush.radialGradient(
                                    0f to accent.copy(alpha = a),
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
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(text = levelText, style = ChargeTheme.typography.display, color = ink)
                    Text(text = statusLine, style = ChargeTheme.typography.body, color = muted)
                }
            }
        }
    }
}

@Composable
internal fun ChargeHeroRingConcentric(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    level: Float,
    currentEnergy: Float,
) {
    RingHeroScaffold(subtitle, charging, currentEnergy) { accent, ink, muted, energy ->
        val infinite = rememberInfiniteTransition(label = "conc")
        val clock by infinite.animateFloat(
            initialValue = 0f,
            targetValue = 3600f,
            animationSpec = infiniteRepeatable(
                animation = tween(3_600_000, easing = LinearEasing),
                repeatMode = RepeatMode.Restart,
            ),
            label = "concClock",
        )
        val heroSize = ChargeTheme.dimens.heroSize
        val heroStroke = ChargeTheme.dimens.heroStroke
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize + 24.dp)) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val c = Offset(size.width / 2f, size.height / 2f)
                val baseR = heroSize.toPx() / 2f
                val strokePx = heroStroke.toPx()
                val spin = if (charging) clock * (40f + 160f * energy) else 0f
                for (i in 0..2) {
                    val r = baseR * (0.72f + i * 0.16f)
                    val a = (0.55f - i * 0.14f) * (0.5f + 0.5f * level)
                    rotate(degrees = spin * (1f - i * 0.25f) * if (i % 2 == 0) 1f else -1f, pivot = c) {
                        drawArc(
                            color = accent.copy(alpha = a),
                            startAngle = -90f + i * 25f,
                            sweepAngle = 220f + level * 100f,
                            useCenter = false,
                            style = Stroke(width = 2.4f + i * 0.6f, cap = StrokeCap.Round),
                            topLeft = Offset(c.x - r, c.y - r),
                            size = Size(r * 2f, r * 2f),
                        )
                    }
                }
                if (charging) {
                    drawCircle(
                        brush = Brush.radialGradient(
                            0f to accent.copy(alpha = 0.16f + 0.2f * energy),
                            1f to Color.Transparent,
                            center = c,
                            radius = baseR * 0.9f,
                        ),
                        radius = baseR * 0.9f,
                        center = c,
                    )
                }
                drawArc(
                    color = accent,
                    startAngle = -90f,
                    sweepAngle = 360f * level,
                    useCenter = false,
                    style = Stroke(width = strokePx, cap = StrokeCap.Round),
                    topLeft = Offset(c.x - baseR * 0.62f, c.y - baseR * 0.62f),
                    size = Size(baseR * 1.24f, baseR * 1.24f),
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = levelText, style = ChargeTheme.typography.display, color = ink)
                Text(text = statusLine, style = ChargeTheme.typography.body, color = muted)
            }
        }
    }
}

@Composable
internal fun ChargeHeroRingPlasma(
    levelText: String,
    statusLine: String,
    subtitle: String,
    charging: Boolean,
    level: Float,
    currentEnergy: Float,
) {
    RingHeroScaffold(subtitle, charging, currentEnergy) { accent, ink, muted, energy ->
        val infinite = rememberInfiniteTransition(label = "plasma")
        val clock by infinite.animateFloat(
            initialValue = 0f,
            targetValue = 3600f,
            animationSpec = infiniteRepeatable(
                animation = tween(3_600_000, easing = LinearEasing),
                repeatMode = RepeatMode.Restart,
            ),
            label = "plasmaClock",
        )
        val heroSize = ChargeTheme.dimens.heroSize
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize + 36.dp)) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val c = Offset(size.width / 2f, size.height / 2f)
                val r = heroSize.toPx() / 2f * 0.92f
                val amp = (2.5f + 5f * energy) * if (charging) 1f else 0.35f
                val phase = clock * (1.2f + 2.2f * energy)
                fun waveRing(pathPhase: Float, alpha: Float, width: Float) {
                    val path = Path()
                    val steps = 72
                    for (i in 0..steps) {
                        val t = i / steps.toFloat()
                        val ang = t * PI.toFloat() * 2f - PI.toFloat() / 2f
                        val rr = r + sin(ang * 3f + pathPhase) * amp +
                            sin(ang * 5f - pathPhase * 1.3f) * amp * 0.4f
                        val x = c.x + cos(ang) * rr
                        val y = c.y + sin(ang) * rr
                        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    path.close()
                    drawPath(
                        path,
                        color = accent.copy(alpha = alpha),
                        style = Stroke(width = width, cap = StrokeCap.Round),
                    )
                }
                waveRing(phase, 0.35f, 5f)
                waveRing(phase * 1.15f + 0.8f, 0.55f, 3.2f)
                waveRing(phase * 0.9f + 1.6f, 0.75f, 2f)
                val progress = Path()
                val sweepSteps = (72 * level).toInt().coerceAtLeast(1)
                for (i in 0..sweepSteps) {
                    val t = i / 72f
                    val ang = t * PI.toFloat() * 2f - PI.toFloat() / 2f
                    val rr = r + sin(ang * 3f + phase) * amp * 0.6f
                    val x = c.x + cos(ang) * rr
                    val y = c.y + sin(ang) * rr
                    if (i == 0) progress.moveTo(x, y) else progress.lineTo(x, y)
                }
                drawPath(
                    progress,
                    color = accent,
                    style = Stroke(width = 4f, cap = StrokeCap.Round),
                )
                if (charging) {
                    for (i in 0..4) {
                        val life = ((clock * (0.6f + energy) + i * 0.19f) % 1f)
                        val y = c.y + r + 8f + life * 28f
                        val x = c.x + sin(life * 8f + i) * (10f + 8f * energy)
                        val a = (1f - abs(life - 0.5f) * 2f).coerceIn(0f, 1f) * 0.5f
                        drawCircle(color = accent.copy(alpha = a), radius = 2.5f + energy, center = Offset(x, y))
                    }
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = levelText, style = ChargeTheme.typography.display, color = ink)
                Text(text = statusLine, style = ChargeTheme.typography.body, color = muted)
            }
        }
    }
}

@Composable
private fun RingHeroScaffold(
    subtitle: String,
    charging: Boolean,
    currentEnergy: Float,
    content: @Composable (accent: Color, ink: Color, muted: Color, energy: Float) -> Unit,
) {
    val accent = ChargeTheme.colors.accent
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted
    val energy = if (charging) currentEnergy.coerceIn(0f, 1f) else 0f
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        content(accent, ink, muted, energy)
        if (charging) {
            Spacer(modifier = Modifier.height(8.dp))
            ChargingChip(accent, boltAlpha = 0.6f + 0.4f * energy)
        }
        Spacer(modifier = Modifier.height(if (charging) 6.dp else 10.dp))
        Text(
            text = subtitle,
            style = ChargeTheme.typography.caption,
            color = muted,
            textAlign = TextAlign.Center,
        )
    }
}
