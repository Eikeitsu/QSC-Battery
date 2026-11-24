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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.sin

/**
 * 首页电量 Hero。
 * 充电态参考系统充电屏：外扩脉冲环 + 弧上微光 + 底部上升气泡，
 * 动效不压在电量数字上（#3）。
 */
@Composable
fun ChargeHero(
    levelText: String,
    percent: Float?,
    statusLine: String,
    subtitle: String,
    charging: Boolean = false,
) {
    val p = (percent ?: 0f).coerceIn(0f, 1f)
    val animated by animateFloatAsState(
        targetValue = p,
        animationSpec = tween(800, easing = FastOutSlowInEasing),
        label = "hero",
    )
    val track = ChargeTheme.colors.stroke
    val progress = ChargeTheme.colors.accent
    val heroSize = ChargeTheme.dimens.heroSize
    val heroStroke = ChargeTheme.dimens.heroStroke
    val display = ChargeTheme.typography.display
    val body = ChargeTheme.typography.body
    val caption = ChargeTheme.typography.caption
    val ink = ChargeTheme.colors.ink
    val muted = ChargeTheme.colors.muted

    val motion = if (charging) rememberChargeHeroMotion() else null

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // 外圈留白给脉冲环扩散，避免裁切
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(heroSize + 36.dp),
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val c = Offset(size.width / 2f, size.height / 2f)
                val ringR = (heroSize.toPx() - heroStroke.toPx()) / 2f

                // 底光
                val glowA = motion?.glowAlpha ?: 0.10f
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(progress.copy(alpha = glowA), Color.Transparent),
                        center = c,
                        radius = ringR * 1.35f,
                    ),
                    radius = ringR * 1.35f,
                    center = c,
                )

                if (motion != null) {
                    // 系统充电常见的外扩脉冲环（错相 3 层）
                    for (i in 0..2) {
                        val phase = (motion.pulse + i / 3f) % 1f
                        val ease = FastOutSlowInEasing.transform(phase)
                        val r = ringR * (1.02f + ease * 0.38f)
                        val a = (1f - ease) * 0.28f
                        drawCircle(
                            color = progress.copy(alpha = a),
                            radius = r,
                            center = c,
                            style = Stroke(width = heroStroke.toPx() * (0.35f + (1f - ease) * 0.25f)),
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
                        color = track,
                        startAngle = -90f,
                        sweepAngle = 360f,
                        useCenter = false,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                        size = arcSize,
                        topLeft = topLeft,
                    )
                    drawArc(
                        brush = Brush.sweepGradient(
                            colors = listOf(
                                progress.copy(alpha = 0.85f),
                                progress,
                                progress.copy(alpha = 0.95f),
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
                        // 弧尾微光：只在进度弧上滑动，不侵入圆心文字
                        rotate(degrees = -90f + 360f * animated - 8f + motion.shimmer * 12f) {
                            drawArc(
                                color = Color.White.copy(alpha = 0.45f * motion.glowAlpha.coerceIn(0.2f, 1f)),
                                startAngle = 0f,
                                sweepAngle = 18f,
                                useCenter = false,
                                style = Stroke(width = stroke * 0.85f, cap = StrokeCap.Round),
                                size = arcSize,
                                topLeft = topLeft,
                            )
                        }
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(text = levelText, style = display, color = ink)
                    Text(text = statusLine, style = body, color = muted)
                }
            }
        }

        if (charging) {
            Spacer(modifier = Modifier.height(2.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(progress.copy(alpha = 0.12f))
                    .padding(horizontal = 10.dp, vertical = 4.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Bolt,
                    contentDescription = null,
                    tint = progress,
                    modifier = Modifier.size(14.dp),
                )
                Text(
                    text = "充电中",
                    style = caption,
                    color = progress,
                    fontWeight = FontWeight.Medium,
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            ChargeBubbleField(
                accent = progress,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .padding(horizontal = 28.dp),
            )
        }

        Spacer(modifier = Modifier.height(if (charging) 4.dp else 10.dp))
        Text(text = subtitle, style = caption, color = muted, textAlign = TextAlign.Center)
    }
}

private data class ChargeHeroMotion(
    val pulse: Float,
    val glowAlpha: Float,
    val shimmer: Float,
    val bubble: Float,
)

@Composable
private fun rememberChargeHeroMotion(): ChargeHeroMotion {
    val infinite = rememberInfiniteTransition(label = "chargeMotion")
    val pulse by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulse",
    )
    val glow by infinite.animateFloat(
        initialValue = 0.12f,
        targetValue = 0.26f,
        animationSpec = infiniteRepeatable(
            animation = tween(1600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glow",
    )
    val shimmer by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2800, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "shimmer",
    )
    val bubble by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(4200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "bubble",
    )
    return ChargeHeroMotion(pulse, glow, shimmer, bubble)
}

/** 底部上升气泡带：参考系统充电屏底部粒子，限定在环下方。 */
@Composable
private fun ChargeBubbleField(
    accent: Color,
    modifier: Modifier = Modifier,
) {
    val infinite = rememberInfiniteTransition(label = "bubbles")
    val t by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(4200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "bubbleT",
    )
    val seeds = remember {
        List(12) { i ->
            BubbleSeed(
                xFrac = (0.08f + (i * 0.079f) % 0.84f),
                size = 2.2f + (i % 5) * 0.9f,
                speed = 0.55f + (i % 4) * 0.12f,
                phase = (i * 0.17f) % 1f,
                sway = 6f + (i % 3) * 4f,
            )
        }
    }

    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        seeds.forEach { b ->
            val life = (t * b.speed + b.phase) % 1f
            val y = h * (1.05f - life * 1.15f)
            val x = w * b.xFrac + sin(life * PI.toFloat() * 2f + b.phase * 6f) * b.sway
            val alpha = when {
                life < 0.12f -> life / 0.12f
                life > 0.75f -> ((1f - life) / 0.25f).coerceIn(0f, 1f)
                else -> 1f
            } * 0.55f
            val r = b.size * (0.7f + life * 0.5f)
            drawCircle(
                color = accent.copy(alpha = alpha),
                radius = r,
                center = Offset(x, y),
            )
            // 高光点，增加一点「液体」感
            drawCircle(
                color = Color.White.copy(alpha = alpha * 0.35f),
                radius = r * 0.35f,
                center = Offset(x - r * 0.25f, y - r * 0.25f),
            )
        }
        // 底部淡雾，衔接气泡源头
        drawRect(
            brush = Brush.verticalGradient(
                colors = listOf(Color.Transparent, accent.copy(alpha = 0.08f)),
                startY = h * 0.45f,
                endY = h,
            ),
        )
    }
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
