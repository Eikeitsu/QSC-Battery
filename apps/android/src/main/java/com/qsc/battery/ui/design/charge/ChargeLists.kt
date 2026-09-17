package com.qsc.battery.ui.design.charge

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun ChargeSection(
    title: String? = null,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (!title.isNullOrBlank()) {
            Text(
                text = title,
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(ChargeTheme.dimens.radiusLg))
                .background(ChargeTheme.colors.surface)
                .border(1.dp, ChargeTheme.colors.stroke, RoundedCornerShape(ChargeTheme.dimens.radiusLg))
                .padding(vertical = 6.dp),
            content = content,
        )
    }
}

@Composable
fun ChargeListRow(
    title: String,
    summary: String? = null,
    value: String? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier,
            )
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = ChargeTheme.typography.body, color = ChargeTheme.colors.ink, fontWeight = FontWeight.Medium)
            if (!summary.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(3.dp))
                Text(text = summary, style = ChargeTheme.typography.caption, color = ChargeTheme.colors.muted)
            }
        }
        if (!value.isNullOrBlank()) {
            Text(
                text = value,
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
        }
        trailing?.invoke(this)
    }
}

@Composable
fun ChargeToggleRow(
    title: String,
    checked: Boolean,
    summary: String? = null,
    enabled: Boolean = true,
    onCheckedChange: (Boolean) -> Unit,
) {
    ChargeListRow(
        title = title,
        summary = summary,
        onClick = if (enabled) ({ onCheckedChange(!checked) }) else null,
        trailing = {
            Switch(
                checked = checked,
                onCheckedChange = if (enabled) onCheckedChange else null,
                enabled = enabled,
                colors = SwitchDefaults.colors(
                    checkedTrackColor = ChargeTheme.colors.accent,
                    checkedThumbColor = ChargeTheme.colors.onAccent,
                ),
            )
        },
    )
}

@Composable
fun ChargeDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(horizontal = 16.dp),
        color = ChargeTheme.colors.stroke,
    )
}
