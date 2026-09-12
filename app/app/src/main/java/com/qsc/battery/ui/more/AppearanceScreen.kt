package com.qsc.battery.ui.more

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.ui.theme.ColorMode
import com.qsc.battery.ui.theme.ThemeSettings
import kotlinx.coroutines.launch

@Composable
fun AppearanceScreen(
    container: AppContainer,
    onBack: () -> Unit,
    onOpenPalette: () -> Unit,
) {
    val settings by container.settingsRepository.settings.collectAsStateWithLifecycle(
        initialValue = ThemeSettings(),
    )
    val scope = rememberCoroutineScope()

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(title = "主题设置", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
                .padding(
                    top = ChargeTheme.dimens.topBarContentGap,
                    bottom = ChargeTheme.dimens.sectionGap,
                ),
            verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
        ) {
            Text(
                text = "选择颜色模式预览块，一键切换明暗与取色。",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )

            Text(
                text = "颜色模式",
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                fontWeight = FontWeight.SemiBold,
            )

            val modes = listOf(
                ColorMode.SYSTEM to "跟随系统",
                ColorMode.LIGHT to "浅色",
                ColorMode.DARK to "深色",
                ColorMode.DARK_AMOLED to "纯黑 AMOLED",
                ColorMode.MONET_SYSTEM to "动态 · 系统",
                ColorMode.MONET_LIGHT to "动态 · 浅色",
                ColorMode.MONET_DARK to "动态 · 深色",
            )
            modes.chunked(2).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    row.forEach { (mode, label) ->
                        val selected = settings.colorMode == mode
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(72.dp)
                                .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
                                .background(
                                    if (selected) ChargeTheme.colors.accent.copy(alpha = 0.12f)
                                    else ChargeTheme.colors.surface,
                                )
                                .border(
                                    width = if (selected) 2.dp else 1.dp,
                                    color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                                    shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd),
                                )
                                .clickable {
                                    scope.launch { container.settingsRepository.setColorMode(mode) }
                                }
                                .padding(12.dp),
                            contentAlignment = Alignment.CenterStart,
                        ) {
                            Text(
                                text = label,
                                style = ChargeTheme.typography.label,
                                color = ChargeTheme.colors.ink,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            )
                        }
                    }
                    if (row.size == 1) Spacer(modifier = Modifier.weight(1f))
                }
            }

            ChargeSection(title = "更多") {
                ChargeListRow(
                    title = "调色板",
                    summary = "种子色与配色风格",
                    onClick = onOpenPalette,
                )
                ChargeDivider()
                ChargeToggleRow(
                    title = "备用桌面图标",
                    checked = settings.alternativeIcon,
                    summary = "切换为环形充电风格图标（部分桌面需稍等刷新）",
                    onCheckedChange = { scope.launch { container.settingsRepository.setAlternativeIcon(it) } },
                )
            }
        }
    }
}
