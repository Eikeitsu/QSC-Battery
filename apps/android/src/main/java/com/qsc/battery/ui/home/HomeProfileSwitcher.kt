package com.qsc.battery.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.FolderCopy
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.design.charge.ChargeTheme

@Composable
internal fun HomeConfigProfileCard(
    activeName: String?,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd)
    val accent = ChargeTheme.colors.accent
    val title = activeName?.takeIf { it.isNotBlank() } ?: "未选择"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.horizontalGradient(
                    listOf(
                        accent.copy(alpha = 0.16f),
                        ChargeTheme.colors.surfaceStrong,
                    ),
                ),
            )
            .border(1.dp, accent.copy(alpha = 0.35f), shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(accent.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Outlined.FolderCopy,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(22.dp),
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "配置档",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )
            Text(
                text = title,
                style = ChargeTheme.typography.title,
                color = ChargeTheme.colors.ink,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Text(
            text = "切换",
            style = ChargeTheme.typography.label,
            color = accent,
            fontWeight = FontWeight.SemiBold,
        )
        Icon(
            imageVector = Icons.Outlined.ExpandMore,
            contentDescription = null,
            tint = accent,
            modifier = Modifier.size(20.dp),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HomeConfigProfileSheet(
    names: List<String>,
    selectedName: String?,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = ChargeTheme.colors.surface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "切换配置档",
                style = ChargeTheme.typography.title,
                color = ChargeTheme.colors.ink,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "应用后写入当前模块配置；可在「我的 → 配置档」管理",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )
            Spacer(modifier = Modifier.size(4.dp))
            if (names.isEmpty()) {
                Text(
                    text = "还没有配置档。先到「我的 → 配置档」保存一份。",
                    style = ChargeTheme.typography.body,
                    color = ChargeTheme.colors.muted,
                    modifier = Modifier.padding(vertical = 12.dp),
                )
            } else {
                names.forEach { name ->
                    val selected = name == selectedName
                    val shape = RoundedCornerShape(14.dp)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(shape)
                            .background(
                                if (selected) {
                                    ChargeTheme.colors.accent.copy(alpha = 0.12f)
                                } else {
                                    ChargeTheme.colors.surfaceStrong
                                },
                            )
                            .border(
                                width = if (selected) 2.dp else 1.dp,
                                color = if (selected) {
                                    ChargeTheme.colors.accent
                                } else {
                                    ChargeTheme.colors.stroke
                                },
                                shape = shape,
                            )
                            .clickable { onSelect(name) }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = name,
                            style = ChargeTheme.typography.body,
                            color = ChargeTheme.colors.ink,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                            modifier = Modifier.weight(1f),
                        )
                        if (selected) {
                            Text(
                                text = "当前",
                                style = ChargeTheme.typography.label,
                                color = ChargeTheme.colors.accent,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                }
            }
        }
    }
}
