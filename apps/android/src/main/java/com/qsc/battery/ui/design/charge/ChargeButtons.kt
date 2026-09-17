package com.qsc.battery.ui.design.charge

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun ChargePrimaryButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    compact: Boolean = false,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(if (compact) 42.dp else ChargeTheme.dimens.primaryButton)
            .clip(shape)
            .background(
                if (enabled) {
                    ChargeTheme.colors.accent
                } else {
                    ChargeTheme.colors.accent.copy(alpha = 0.35f)
                },
            )
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = if (compact) ChargeTheme.typography.body else ChargeTheme.typography.headline,
            color = ChargeTheme.colors.onAccent,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/** 行内文字操作，避免信息卡下再叠全宽主按钮。 */
@Composable
fun ChargeTextAction(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Text(
        text = text,
        style = ChargeTheme.typography.label,
        color = if (enabled) ChargeTheme.colors.accent else ChargeTheme.colors.muted,
        fontWeight = FontWeight.SemiBold,
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 4.dp, vertical = 8.dp),
    )
}

/** 行尾紧凑更新按钮（tonal）。 */
@Composable
fun ChargeTonalButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(999.dp))
            .background(
                if (enabled) {
                    ChargeTheme.colors.accent.copy(alpha = 0.16f)
                } else {
                    ChargeTheme.colors.stroke.copy(alpha = 0.4f)
                },
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = ChargeTheme.typography.label,
            color = if (enabled) ChargeTheme.colors.accent else ChargeTheme.colors.muted,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
fun ChargeSecondaryButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    equalHeight: Boolean = false,
    height: Dp? = null,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd)
    val h = height ?: if (equalHeight) ChargeTheme.dimens.primaryButton else ChargeTheme.dimens.secondaryButton
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(h)
            .clip(shape)
            .border(1.dp, ChargeTheme.colors.stroke, shape)
            .background(ChargeTheme.colors.surface)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = ChargeTheme.typography.body,
            color = if (enabled) ChargeTheme.colors.ink else ChargeTheme.colors.muted,
            fontWeight = FontWeight.Medium,
        )
    }
}
