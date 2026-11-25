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
import com.qsc.battery.ui.theme.ChargeHeroStyle
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
                    top = ChargeTheme.dimens.pageContentTop,
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
                                    if (selected) {
                                        ChargeTheme.colors.accent.copy(alpha = 0.12f)
                                    } else {
                                        ChargeTheme.colors.surface
                                    },
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

            Text(
                text = "首页充电动画",
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "仅影响首页电量 Hero；插电充电时可见动效差异。",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )

            val heroStyles = listOf(
                ChargeHeroStyle.Pulse to ("柔光脉冲" to "默认 · 外扩柔光环与软边粒子"),
                ChargeHeroStyle.Orbit to ("弧光流转" to "进度环弧光拖尾旋转"),
                ChargeHeroStyle.Battery to ("竖电量卡" to "左侧竖电池，右侧状态信息"),
            )
            heroStyles.forEach { (style, labels) ->
                val (title, summary) = labels
                val selected = settings.chargeHeroStyle == style
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
                        .background(
                            if (selected) {
                                ChargeTheme.colors.accent.copy(alpha = 0.12f)
                            } else {
                                ChargeTheme.colors.surface
                            },
                        )
                        .border(
                            width = if (selected) 2.dp else 1.dp,
                            color = if (selected) ChargeTheme.colors.accent else ChargeTheme.colors.stroke,
                            shape = RoundedCornerShape(ChargeTheme.dimens.radiusMd),
                        )
                        .clickable {
                            scope.launch { container.settingsRepository.setChargeHeroStyle(style) }
                        }
                        .padding(horizontal = 14.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = title,
                            style = ChargeTheme.typography.label,
                            color = ChargeTheme.colors.ink,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = summary,
                            style = ChargeTheme.typography.caption,
                            color = ChargeTheme.colors.muted,
                        )
                    }
                    if (selected) {
                        Text(
                            text = "使用中",
                            style = ChargeTheme.typography.caption,
                            color = ChargeTheme.colors.accent,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
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
                    summary = "环形充电风格（可与动态电量同时使用）",
                    onCheckedChange = { scope.launch { container.settingsRepository.setAlternativeIcon(it) } },
                )
                ChargeDivider()
                ChargeToggleRow(
                    title = "动态电量图标",
                    checked = settings.dynamicBatteryIcon,
                    summary = "默认关闭。按约 10% 分档；打开应用或插拔电时刷新（切入口可能闪一下）",
                    onCheckedChange = { scope.launch { container.settingsRepository.setDynamicBatteryIcon(it) } },
                )
                ChargeDivider()
                ChargeToggleRow(
                    title = "首页显示配置档",
                    checked = settings.homeProfileSwitcher,
                    summary = "在首页展示当前配置档，点按可快捷切换",
                    onCheckedChange = { scope.launch { container.settingsRepository.setHomeProfileSwitcher(it) } },
                )
            }
        }
    }
}
