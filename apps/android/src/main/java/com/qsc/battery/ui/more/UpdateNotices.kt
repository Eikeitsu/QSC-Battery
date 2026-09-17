package com.qsc.battery.ui.more

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.design.charge.ChargeTextAction
import com.qsc.battery.ui.design.charge.ChargeTheme

internal enum class UpdateNoticeTone { Info, Warn }

@Composable
internal fun UpdateInlineNotice(
    text: String,
    tone: UpdateNoticeTone,
    action: String? = null,
    actionEnabled: Boolean = true,
    onAction: (() -> Unit)? = null,
) {
    val bg = when (tone) {
        UpdateNoticeTone.Info -> ChargeTheme.colors.accent.copy(alpha = 0.10f)
        UpdateNoticeTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.10f)
    }
    val border = when (tone) {
        UpdateNoticeTone.Info -> ChargeTheme.colors.accent.copy(alpha = 0.22f)
        UpdateNoticeTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.24f)
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(bg)
            .border(1.dp, border, RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = text,
            style = ChargeTheme.typography.caption,
            color = ChargeTheme.colors.ink,
            modifier = Modifier.weight(1f),
        )
        if (!action.isNullOrBlank() && onAction != null) {
            ChargeTextAction(
                text = action,
                enabled = actionEnabled,
                onClick = onAction,
            )
        }
    }
}
