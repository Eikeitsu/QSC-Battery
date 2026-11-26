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
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
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
        glyphWidth = if (horizontal) 148.dp else 86.dp,
        glyphHeight = if (horizontal) 82.dp else 132.dp,
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
        glyphWidth = if (horizontal) 148.dp else 86.dp,
        glyphHeight = if (horizontal) 82.dp else 132.dp,
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
        if (horizontal) {
            val g = horizontalBatteryGeom()
            drawHorizontalBatteryShell(g, ink, track, frameAlpha = if (charging) 0.72f + 0.28f * pulse else 0.88f)
            val clip = Path().apply {
                addRoundRect(
                    RoundRect(
                        left = g.innerL,
                        top = g.innerT,
                        right = g.innerL + g.innerW,
                        bottom = g.innerT + g.innerH,
                        cornerRadius = CornerRadius(g.innerRx),
                    ),
                )
            }
            clipPath(clip) {
                val segments = 5
                val gap = g.innerH * 0.08f
                val segW = (g.innerW - gap * (segments - 1)) / segments
                val lit = (level.coerceIn(0f, 1f) * segments).toInt().coerceIn(0, segments)
                val partial = (level.coerceIn(0f, 1f) * segments) - lit
                val segRx = (g.innerH * 0.18f).coerceAtMost(g.innerRx)
                for (i in 0 until segments) {
                    val x = g.innerL + i * (segW + gap)
                    val fill = when {
                        i < lit -> 1f
                        i == lit -> partial
                        else -> 0f
                    }
                    if (fill <= 0.02f) continue
                    val t = (i + 0.5f) / segments
                    val col = blockColor(t, accent).copy(
                        alpha = if (charging && i == lit.coerceAtMost(segments - 1)) {
                            0.78f + 0.22f * pulse
                        } else {
                            0.96f
                        },
                    )
                    drawRoundRect(
                        color = col,
                        topLeft = Offset(x, g.innerT),
                        size = Size(segW * fill.coerceAtLeast(0.12f), g.innerH),
                        cornerRadius = CornerRadius(segRx),
                    )
                }
            }
            if (charging) drawBatteryBolt(g, ink)
        } else {
            val stroke = (min(w, h) * 0.055f).coerceIn(3.5f, 6f)
            val bodyW = w * 0.88f
            val bodyLeft = (w - bodyW) / 2f
            val capH = h * 0.08f
            val bodyTop = capH * 0.7f
            val bodyH = h - bodyTop - h * 0.02f
            val bodyRx = bodyW * 0.18f
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
                cornerRadius = CornerRadius(bodyRx),
                style = Stroke(width = stroke),
            )
            val pad = stroke * 1.2f
            val innerL = bodyLeft + pad
            val innerT = bodyTop + pad
            val innerW = bodyW - pad * 2f
            val innerH = bodyH - pad * 2f
            val innerRx = (bodyRx - pad).coerceAtLeast(4f)
            val clip = Path().apply {
                addRoundRect(
                    RoundRect(
                        left = innerL,
                        top = innerT,
                        right = innerL + innerW,
                        bottom = innerT + innerH,
                        cornerRadius = CornerRadius(innerRx),
                    ),
                )
            }
            clipPath(clip) {
                val segments = 5
                val gap = 5f
                val segH = (innerH - gap * (segments - 1)) / segments
                val lit = (level.coerceIn(0f, 1f) * segments).toInt().coerceIn(0, segments)
                val partial = (level.coerceIn(0f, 1f) * segments) - lit
                val segRx = (innerW * 0.08f).coerceAtMost(innerRx)
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
                        cornerRadius = CornerRadius(segRx),
                    )
                }
            }
        }
    }
}

/** 对齐 WebUI BatteryGlyph：viewBox 48×26、frame 40×19 rx≈4、内填充 inset≈2.5。 */
private data class HBattGeom(
    val stroke: Float,
    val bodyL: Float,
    val bodyT: Float,
    val bodyW: Float,
    val bodyH: Float,
    val bodyRx: Float,
    val capL: Float,
    val capT: Float,
    val capW: Float,
    val capH: Float,
    val innerL: Float,
    val innerT: Float,
    val innerW: Float,
    val innerH: Float,
    val innerRx: Float,
    val tipRx: Float,
)

private fun DrawScope.horizontalBatteryGeom(): HBattGeom {
    val w = size.width
    val h = size.height
    // 壳体加高：约占画布 84%，圆角比 WebUI 4/19
    val stroke = (h * 0.085f).coerceIn(3.4f, 5.8f)
    val bodyH = h * 0.84f
    val bodyT = (h - bodyH) / 2f
    val capW = w * 0.055f
    val bodyL = stroke * 0.55f
    val bodyW = w - bodyL - capW - stroke * 0.35f
    val bodyRx = bodyH * (4f / 19f)
    val capH = bodyH * 0.42f
    val capT = bodyT + (bodyH - capH) / 2f
    val capL = bodyL + bodyW + stroke * 0.05f
    val inset = stroke * 1.15f
    val innerL = bodyL + inset
    val innerT = bodyT + inset
    val innerW = bodyW - inset * 2f
    val innerH = bodyH - inset * 2f
    val innerRx = (bodyRx - inset * 0.65f).coerceAtLeast(bodyH * 0.08f)
    val tipRx = (innerH * (1.5f / 14f)).coerceIn(2.2f, 5f)
    return HBattGeom(
        stroke = stroke,
        bodyL = bodyL,
        bodyT = bodyT,
        bodyW = bodyW,
        bodyH = bodyH,
        bodyRx = bodyRx,
        capL = capL,
        capT = capT,
        capW = capW,
        capH = capH,
        innerL = innerL,
        innerT = innerT,
        innerW = innerW,
        innerH = innerH,
        innerRx = innerRx,
        tipRx = tipRx,
    )
}

private fun DrawScope.drawHorizontalBatteryShell(
    g: HBattGeom,
    ink: Color,
    track: Color,
    frameAlpha: Float,
) {
    drawRoundRect(
        color = ink.copy(alpha = frameAlpha),
        topLeft = Offset(g.bodyL, g.bodyT),
        size = Size(g.bodyW, g.bodyH),
        cornerRadius = CornerRadius(g.bodyRx),
        style = Stroke(width = g.stroke),
    )
    drawRoundRect(
        color = track.copy(alpha = 0.85f),
        topLeft = Offset(g.capL, g.capT),
        size = Size(g.capW, g.capH),
        cornerRadius = CornerRadius(g.capW * 0.45f),
    )
}

private fun DrawScope.drawBatteryBolt(g: HBattGeom, ink: Color) {
    val cx = g.innerL + g.innerW * 0.52f
    val cy = g.innerT + g.innerH * 0.5f
    val s = g.innerH * 0.42f
    val bolt = Path().apply {
        moveTo(cx + s * 0.08f, cy - s * 0.55f)
        lineTo(cx - s * 0.28f, cy + s * 0.05f)
        lineTo(cx + s * 0.02f, cy + s * 0.05f)
        lineTo(cx - s * 0.1f, cy + s * 0.55f)
        lineTo(cx + s * 0.32f, cy - s * 0.08f)
        lineTo(cx + s * 0.02f, cy - s * 0.08f)
        close()
    }
    drawPath(bolt, color = ink.copy(alpha = 0.72f))
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
            animation = tween((2400 - 900 * energy).toInt().coerceIn(1100, 2400), easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "solidShimmer",
    )
    val pulse by infinite.animateFloat(
        initialValue = 0.88f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2400, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "solidPulse",
    )
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val lvl = level.coerceIn(0f, 1f)
        if (horizontal) {
            val g = horizontalBatteryGeom()
            drawHorizontalBatteryShell(
                g,
                ink,
                track,
                frameAlpha = if (charging) 0.72f + 0.28f * pulse else 0.9f,
            )
            val clip = Path().apply {
                addRoundRect(
                    RoundRect(
                        left = g.innerL,
                        top = g.innerT,
                        right = g.innerL + g.innerW,
                        bottom = g.innerT + g.innerH,
                        cornerRadius = CornerRadius(g.innerRx),
                    ),
                )
            }
            clipPath(clip) {
                val fillW = g.innerW * lvl
                if (fillW > 1.5f) {
                    // 低电量偏暖，对齐 WebUI ≤30% 警示色
                    val fillColor = when {
                        lvl <= 0.15f -> Color(0xFFEF4444)
                        lvl <= 0.30f -> Color(0xFFF59E0B)
                        else -> accent
                    }
                    drawRoundRect(
                        brush = Brush.horizontalGradient(
                            colors = listOf(fillColor.copy(alpha = 0.82f), fillColor),
                        ),
                        topLeft = Offset(g.innerL, g.innerT),
                        size = Size(fillW, g.innerH),
                        cornerRadius = CornerRadius(g.tipRx),
                    )
                    if (charging) {
                        val band = g.innerH * 0.9f
                        val sx = g.innerL - band + (g.innerW + band * 2f) * shimmer
                        drawRect(
                            brush = Brush.horizontalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    Color.White.copy(alpha = 0.08f),
                                    Color.White.copy(alpha = 0.32f),
                                    Color.White.copy(alpha = 0.08f),
                                    Color.Transparent,
                                ),
                            ),
                            topLeft = Offset(sx, g.innerT),
                            size = Size(band, g.innerH),
                        )
                    }
                }
            }
            if (charging) drawBatteryBolt(g, ink)
        } else {
            val stroke = (min(w, h) * 0.055f).coerceIn(3.5f, 6f)
            val bodyW = w * 0.88f
            val bodyLeft = (w - bodyW) / 2f
            val capH = h * 0.08f
            val bodyTop = capH * 0.7f
            val bodyH = h - bodyTop - h * 0.02f
            val bodyRx = bodyW * 0.18f
            drawRoundRect(
                color = ink.copy(alpha = if (charging) 0.5f + 0.2f * pulse else 0.55f),
                topLeft = Offset((w - bodyW * 0.4f) / 2f, 0f),
                size = Size(bodyW * 0.4f, capH),
                cornerRadius = CornerRadius(capH * 0.4f),
            )
            drawRoundRect(
                color = ink.copy(alpha = if (charging) 0.5f + 0.25f * pulse else 0.55f),
                topLeft = Offset(bodyLeft, bodyTop),
                size = Size(bodyW, bodyH),
                cornerRadius = CornerRadius(bodyRx),
                style = Stroke(width = stroke),
            )
            val pad = stroke * 1.2f
            val innerL = bodyLeft + pad
            val innerW = bodyW - pad * 2f
            val innerHMax = bodyH - pad * 2f
            val innerRx = (bodyRx - pad).coerceAtLeast(4f)
            val tipRx = (innerW * 0.08f).coerceIn(3f, 8f)
            val clip = Path().apply {
                addRoundRect(
                    RoundRect(
                        left = innerL,
                        top = bodyTop + pad,
                        right = innerL + innerW,
                        bottom = bodyTop + pad + innerHMax,
                        cornerRadius = CornerRadius(innerRx),
                    ),
                )
            }
            clipPath(clip) {
                val fillH = innerHMax * lvl
                val innerT = bodyTop + pad + (innerHMax - fillH)
                if (fillH > 1.5f) {
                    val fillColor = when {
                        lvl <= 0.15f -> Color(0xFFEF4444)
                        lvl <= 0.30f -> Color(0xFFF59E0B)
                        else -> accent
                    }
                    drawRoundRect(
                        brush = Brush.verticalGradient(
                            colors = listOf(fillColor.copy(alpha = 0.78f), fillColor),
                        ),
                        topLeft = Offset(innerL, innerT),
                        size = Size(innerW, fillH),
                        cornerRadius = CornerRadius(tipRx),
                    )
                    if (charging) {
                        val band = innerW * 0.35f
                        val sy = innerT + fillH - (fillH + band) * shimmer
                        drawRect(
                            brush = Brush.verticalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    Color.White.copy(alpha = 0.3f),
                                    Color.Transparent,
                                ),
                            ),
                            topLeft = Offset(innerL, sy),
                            size = Size(innerW, band),
                        )
                    }
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
    // 中心已有闪电：徽标放环内状态行下，避免环外再挂一枚
    RingHeroScaffold(subtitle, charging, currentEnergy, chipBelowRing = false) { accent, ink, muted, energy ->
        val infinite = rememberInfiniteTransition(label = "neon")
        val breath by infinite.animateFloat(
            initialValue = 0.55f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween((1200 - 500 * energy).toInt().coerceIn(500, 1200), easing = FastOutSlowInEasing),
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
                if (charging) {
                    Spacer(modifier = Modifier.height(6.dp))
                    ChargingChip(accent, boltAlpha = breath)
                }
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
    // 环内已是液面/粘团：徽标放环心文字下，不挡底部上涌
    RingHeroScaffold(subtitle, charging, currentEnergy, chipBelowRing = false) { accent, ink, muted, energy ->
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
            List(10) { i ->
                floatArrayOf(
                    0.12f + (i * 0.085f) % 0.76f,
                    3.2f + (i % 5) * 1.6f,
                    0.45f + (i % 4) * 0.14f,
                    (i * 0.19f) % 1f,
                )
            }
        }
        val heroSize = ChargeTheme.dimens.heroSize
        val heroStroke = ChargeTheme.dimens.heroStroke
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize + 36.dp)) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val c = Offset(size.width / 2f, size.height / 2f)
                val stroke = heroStroke.toPx()
                val ringR = (heroSize.toPx() - stroke) / 2f
                val lvl = level.coerceIn(0f, 1f)
                val surfaceY = c.y + ringR - 2f * ringR * lvl
                val waveAmp = (4.5f + 5.5f * energy) * if (charging) 1f else 0.45f
                val phase = clock * (1.15f + 1.4f * energy)

                drawCircle(
                    brush = Brush.radialGradient(
                        0f to accent.copy(alpha = 0.1f + 0.08f * energy),
                        1f to Color.Transparent,
                        center = c,
                        radius = ringR * 1.05f,
                    ),
                    radius = ringR * 1.05f,
                    center = c,
                )

                val disc = Path().apply {
                    addOval(Rect(c.x - ringR, c.y - ringR, c.x + ringR, c.y + ringR))
                }
                clipPath(disc) {
                    if (lvl > 0.015f) {
                        fun surfaceAt(x: Float, ph: Float, amp: Float): Float {
                            val t = ((x - (c.x - ringR)) / (ringR * 2f)).coerceIn(0f, 1f)
                            return surfaceY +
                                sin(t * PI.toFloat() * 2.2f + ph) * amp +
                                sin(t * PI.toFloat() * 4.1f - ph * 1.35f) * amp * 0.38f
                        }
                        val back = Path().apply {
                            val steps = 56
                            val left = c.x - ringR
                            val right = c.x + ringR
                            moveTo(left, c.y + ringR + 4f)
                            for (i in 0..steps) {
                                val x = left + (right - left) * (i / steps.toFloat())
                                lineTo(x, surfaceAt(x, phase * 0.85f + 0.7f, waveAmp * 0.7f))
                            }
                            lineTo(right, c.y + ringR + 4f)
                            close()
                        }
                        drawPath(back, color = accent.copy(alpha = 0.28f))
                        val front = Path().apply {
                            val steps = 56
                            val left = c.x - ringR
                            val right = c.x + ringR
                            moveTo(left, c.y + ringR + 4f)
                            for (i in 0..steps) {
                                val x = left + (right - left) * (i / steps.toFloat())
                                lineTo(x, surfaceAt(x, phase, waveAmp))
                            }
                            lineTo(right, c.y + ringR + 4f)
                            close()
                        }
                        drawPath(
                            front,
                            brush = Brush.verticalGradient(
                                colors = listOf(
                                    accent.copy(alpha = 0.42f),
                                    accent.copy(alpha = 0.82f),
                                ),
                                startY = surfaceY - waveAmp,
                                endY = c.y + ringR,
                            ),
                        )
                        // 液面高光
                        val gloss = Path().apply {
                            val steps = 40
                            val left = c.x - ringR * 0.92f
                            val right = c.x + ringR * 0.92f
                            moveTo(left, surfaceAt(left, phase, waveAmp))
                            for (i in 1..steps) {
                                val x = left + (right - left) * (i / steps.toFloat())
                                lineTo(x, surfaceAt(x, phase, waveAmp))
                            }
                        }
                        drawPath(
                            gloss,
                            color = Color.White.copy(alpha = 0.28f + 0.12f * energy),
                            style = Stroke(width = 2.2f, cap = StrokeCap.Round),
                        )
                    }
                    if (charging) {
                        val speed = 0.4f + 1.1f * energy
                        seeds.forEach { s ->
                            val life = ((clock * s[2] * speed) + s[3]) % 1f
                            val rise = life * ringR * (1.15f + 0.35f * lvl)
                            val y = c.y + ringR * 0.92f - rise
                            if (y > surfaceY + 4f) return@forEach
                            val x = c.x - ringR * 0.75f + ringR * 1.5f * s[0] +
                                sin(life * 7f + s[3]) * (6f + 6f * energy)
                            val r = s[1] * (0.75f + life * 0.55f) * (0.75f + 0.45f * energy)
                            val a = when {
                                life < 0.12f -> life / 0.12f
                                life > 0.7f -> ((1f - life) / 0.3f).coerceIn(0f, 1f)
                                else -> 1f
                            } * 0.55f
                            drawCircle(
                                brush = Brush.radialGradient(
                                    0f to Color.White.copy(alpha = a * 0.85f),
                                    0.45f to accent.copy(alpha = a),
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

                drawCircle(
                    color = accent.copy(alpha = 0.92f),
                    radius = ringR,
                    center = c,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                )
                // 进度弧暗示液位
                drawArc(
                    color = accent.copy(alpha = 0.35f),
                    startAngle = -90f,
                    sweepAngle = 360f * lvl,
                    useCenter = false,
                    style = Stroke(width = stroke * 0.45f, cap = StrokeCap.Round),
                    topLeft = Offset(c.x - ringR, c.y - ringR),
                    size = Size(ringR * 2f, ringR * 2f),
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = levelText, style = ChargeTheme.typography.display, color = ink)
                Text(text = statusLine, style = ChargeTheme.typography.body, color = muted)
                if (charging) {
                    Spacer(modifier = Modifier.height(6.dp))
                    ChargingChip(accent, boltAlpha = 0.65f + 0.35f * energy)
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
    // 环缘/底缘粒子较多：徽标放环心，避免和轨道粒子抢底边
    RingHeroScaffold(subtitle, charging, currentEnergy, chipBelowRing = false) { accent, ink, muted, energy ->
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
        val heroStroke = ChargeTheme.dimens.heroStroke
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(heroSize + 40.dp)) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val c = Offset(size.width / 2f, size.height / 2f)
                val baseR = heroSize.toPx() / 2f * 0.9f
                val stroke = heroStroke.toPx()
                val lvl = level.coerceIn(0f, 1f)
                val amp = (5f + 7f * energy) * if (charging) 1f else 0.55f
                val phase = clock * (1.6f + 2.4f * energy)

                drawCircle(
                    brush = Brush.radialGradient(
                        0f to accent.copy(alpha = 0.14f + 0.18f * energy * if (charging) 1f else 0.4f),
                        0.55f to accent.copy(alpha = 0.05f),
                        1f to Color.Transparent,
                        center = c,
                        radius = baseR * 1.15f,
                    ),
                    radius = baseR * 1.15f,
                    center = c,
                )

                fun waveRing(pathPhase: Float, radius: Float, alpha: Float, width: Float) {
                    val path = Path()
                    val steps = 96
                    for (i in 0..steps) {
                        val t = i / steps.toFloat()
                        val ang = t * PI.toFloat() * 2f - PI.toFloat() / 2f
                        val rr = radius +
                            sin(ang * 3f + pathPhase) * amp +
                            sin(ang * 5f - pathPhase * 1.25f) * amp * 0.45f +
                            sin(ang * 7f + pathPhase * 0.6f) * amp * 0.18f
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

                // 外层柔波 → 中层 → 内层实波
                waveRing(phase * 0.75f, baseR * 1.06f, 0.22f, 6.5f)
                waveRing(phase, baseR, 0.42f, 4.2f)
                waveRing(phase * 1.2f + 0.9f, baseR * 0.94f, 0.7f, 2.6f)

                // 进度：沿波纹环扫过，加宽更明显
                val progress = Path()
                val sweepSteps = (96 * lvl).toInt().coerceAtLeast(2)
                for (i in 0..sweepSteps) {
                    val t = i / 96f
                    val ang = t * PI.toFloat() * 2f - PI.toFloat() / 2f
                    val rr = baseR +
                        sin(ang * 3f + phase) * amp * 0.55f +
                        sin(ang * 5f - phase * 1.25f) * amp * 0.25f
                    val x = c.x + cos(ang) * rr
                    val y = c.y + sin(ang) * rr
                    if (i == 0) progress.moveTo(x, y) else progress.lineTo(x, y)
                }
                drawPath(
                    progress,
                    color = accent.copy(alpha = 0.35f),
                    style = Stroke(width = stroke * 1.8f, cap = StrokeCap.Round),
                )
                drawPath(
                    progress,
                    color = accent,
                    style = Stroke(width = stroke * 0.95f, cap = StrokeCap.Round),
                )

                // 轨道底环，避免空窗看不清
                drawCircle(
                    color = accent.copy(alpha = 0.18f),
                    radius = baseR,
                    center = c,
                    style = Stroke(width = stroke * 0.55f),
                )

                if (charging) {
                    for (i in 0..7) {
                        val life = ((clock * (0.85f + energy) + i * 0.13f) % 1f)
                        val ang = life * PI.toFloat() * 2f + i * 0.7f
                        val rr = baseR * (0.55f + 0.4f * ((sin(life * PI.toFloat() * 2f) + 1f) * 0.5f))
                        val x = c.x + cos(ang) * rr
                        val y = c.y + sin(ang) * rr
                        val a = (1f - abs(life - 0.5f) * 2f).coerceIn(0f, 1f) * (0.35f + 0.35f * energy)
                        drawCircle(
                            brush = Brush.radialGradient(
                                0f to Color.White.copy(alpha = a),
                                1f to Color.Transparent,
                                center = Offset(x, y),
                                radius = 5f + 4f * energy,
                            ),
                            radius = 5f + 4f * energy,
                            center = Offset(x, y),
                        )
                    }
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = levelText, style = ChargeTheme.typography.display, color = ink)
                Text(text = statusLine, style = ChargeTheme.typography.body, color = muted)
                if (charging) {
                    Spacer(modifier = Modifier.height(6.dp))
                    ChargingChip(accent, boltAlpha = 0.6f + 0.4f * energy)
                }
            }
        }
    }
}

/**
 * @param chipBelowRing 是否在环外下方放「充电中」徽标；部分效果会改在环内自放。
 */
@Composable
private fun RingHeroScaffold(
    subtitle: String,
    charging: Boolean,
    currentEnergy: Float,
    chipBelowRing: Boolean = true,
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
        if (charging && chipBelowRing) {
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
