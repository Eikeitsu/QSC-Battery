package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.moriafly.salt.ui.Item
import com.moriafly.salt.ui.ItemCheck
import com.moriafly.salt.ui.ItemOuterTitle
import com.moriafly.salt.ui.ItemSwitcher
import com.moriafly.salt.ui.RoundedColumn
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text
import com.moriafly.salt.ui.UnstableSaltUiApi
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.AppPage
import com.qsc.battery.ui.design.AppTitleBar
import com.qsc.battery.ui.theme.ColorMode
import com.qsc.battery.ui.theme.ThemeSettings
import kotlinx.coroutines.launch

@OptIn(UnstableSaltUiApi::class)
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
        Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        AppTitleBar(title = "主题设置", onBack = onBack)
        AppPage(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            includeStatusSpacer = false,
        ) {
            Text(
                text = "Salt 列表语言 + 沉浸系统栏。仅切换明暗与取色。",
                style = SaltTheme.textStyles.sub,
                color = SaltTheme.colors.subText,
            )

            ItemOuterTitle(text = "颜色模式")
            RoundedColumn {
                ColorMode.entries.forEach { mode ->
                    ItemCheck(
                        state = settings.colorMode == mode,
                        onChange = {
                            if (it) scope.launch { container.settingsRepository.setColorMode(mode) }
                        },
                        text = modeLabel(mode),
                    )
                }
            }

            ItemOuterTitle(text = "更多")
            RoundedColumn {
                Item(
                    onClick = onOpenPalette,
                    text = "调色板",
                    sub = "种子色与 PaletteStyle",
                )
                ItemSwitcher(
                    state = settings.alternativeIcon,
                    onChange = { scope.launch { container.settingsRepository.setAlternativeIcon(it) } },
                    text = "备用桌面图标",
                    sub = "切换启动器图标",
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
