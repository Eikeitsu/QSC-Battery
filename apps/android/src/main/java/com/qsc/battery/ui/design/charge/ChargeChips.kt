package com.qsc.battery.ui.design.charge

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

enum class ChargeChipTone { Neutral, Ok, Update, Warn }

@Composable
fun ChargeStatusChip(
    text: String,
    tone: ChargeChipTone,
    modifier: Modifier = Modifier,
) {
    val bg = when (tone) {
        ChargeChipTone.Neutral -> ChargeTheme.colors.surfaceStrong
        ChargeChipTone.Ok -> ChargeTheme.colors.success.copy(alpha = 0.14f)
        ChargeChipTone.Update -> ChargeTheme.colors.accent.copy(alpha = 0.14f)
        ChargeChipTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.12f)
    }
    val fg = when (tone) {
        ChargeChipTone.Neutral -> ChargeTheme.colors.muted
        ChargeChipTone.Ok -> ChargeTheme.colors.success
        ChargeChipTone.Update -> ChargeTheme.colors.accent
        ChargeChipTone.Warn -> ChargeTheme.colors.danger
    }
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(999.dp))
            .background(bg)
            .padding(horizontal = 8.dp, vertical = 3.dp),
    ) {
        Text(
            text = text,
            style = ChargeTheme.typography.caption,
            color = fg,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

enum class BannerTone { Info, Warn, Ok }

@Composable
fun ChargeBanner(text: String, tone: BannerTone = BannerTone.Info) {
    val bg = when (tone) {
        BannerTone.Info -> ChargeTheme.colors.accent.copy(alpha = 0.10f)
        BannerTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.10f)
        BannerTone.Ok -> ChargeTheme.colors.success.copy(alpha = 0.12f)
    }
    val border = when (tone) {
        BannerTone.Info -> ChargeTheme.colors.accent.copy(alpha = 0.25f)
        BannerTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.28f)
        BannerTone.Ok -> ChargeTheme.colors.success.copy(alpha = 0.28f)
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(bg)
            .border(1.dp, border, RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .padding(16.dp),
    ) {
        Text(text = text, style = ChargeTheme.typography.body, color = ChargeTheme.colors.ink)
    }
}

@Composable
fun ChargeSegmented(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(ChargeTheme.colors.surfaceStrong.copy(alpha = 0.55f))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        options.forEachIndexed { index, label ->
            val selected = index == selectedIndex
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .background(
                        if (selected) {
                            ChargeTheme.colors.surface
                        } else {
                            Color.Transparent
                        },
                    )
                    .clickable { onSelect(index) }
                    .padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = label,
                    style = ChargeTheme.typography.label,
                    color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.muted,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}
