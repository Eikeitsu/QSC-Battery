package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.PrefAction
import com.qsc.battery.ui.design.PrefSwitch
import com.qsc.battery.ui.design.VoltPage
import com.qsc.battery.ui.design.VoltScaffold
import com.qsc.battery.ui.design.VoltSection
import com.qsc.battery.ui.design.VoltSectionLabel
import com.qsc.battery.ui.design.VoltTopBar
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

    VoltScaffold(
        topBar = { VoltTopBar(title = "主题设置", onBack = onBack) },
    ) { padding ->
        VoltPage(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
            applyStatusBars = false,
        ) {
            Text(
                "Volt 单一界面语言：青绿能量色、沉浸系统栏、分组列表。仅切换明暗与取色。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            VoltSectionLabel("颜色模式")
            VoltSection {
                ColorMode.entries.forEach { mode ->
                    PrefAction(
                        title = modeLabel(mode),
                        summary = if (settings.colorMode == mode) "当前" else null,
                    ) { scope.launch { container.settingsRepository.setColorMode(mode) } }
                }
            }

            VoltSectionLabel("更多")
            VoltSection {
                PrefAction("调色板", "种子色与 PaletteStyle", onClick = onOpenPalette)
                PrefSwitch(
                    title = "备用桌面图标",
                    summary = "切换启动器图标",
                    checked = settings.alternativeIcon,
                    onCheckedChange = { scope.launch { container.settingsRepository.setAlternativeIcon(it) } },
                )
            }
        }
    }
}

private fun modeLabel(mode: ColorMode): String = when (mode) {
    ColorMode.SYSTEM -> "跟随系统"
    ColorMode.LIGHT -> "浅色"
    ColorMode.DARK -> "深色"
    ColorMode.MONET_SYSTEM -> "动态取色 · 跟随系统"
    ColorMode.MONET_LIGHT -> "动态取色 · 浅色"
    ColorMode.MONET_DARK -> "动态取色 · 深色"
    ColorMode.DARK_AMOLED -> "纯黑 AMOLED"
}
