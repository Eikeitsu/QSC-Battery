package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.components.PrefAction
import com.qsc.battery.ui.components.PrefSwitch
import com.qsc.battery.ui.components.QscBody
import com.qsc.battery.ui.components.QscGroup
import com.qsc.battery.ui.components.QscSectionLabel
import com.qsc.battery.ui.theme.ColorMode
import com.qsc.battery.ui.theme.ThemeSettings
import com.qsc.battery.ui.theme.UiMode
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("主题设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            QscSectionLabel("界面风格")
            QscGroup {
                QscBody(spacedBy = 10.dp) {
                    Text(
                        "Pulse 偏表现与大字号；Ledger 偏系统设置密度。均为原生 Compose，非网页皮肤。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        SegmentedButton(
                            selected = settings.uiMode == UiMode.Pulse,
                            onClick = { scope.launch { container.settingsRepository.setUiMode(UiMode.Pulse) } },
                            shape = SegmentedButtonDefaults.itemShape(0, 2),
                        ) { Text("Pulse") }
                        SegmentedButton(
                            selected = settings.uiMode == UiMode.Ledger,
                            onClick = { scope.launch { container.settingsRepository.setUiMode(UiMode.Ledger) } },
                            shape = SegmentedButtonDefaults.itemShape(1, 2),
                        ) { Text("Ledger") }
                    }
                }
            }

            QscSectionLabel("颜色模式")
            QscGroup {
                ColorMode.entries.forEach { mode ->
                    PrefAction(
                        title = modeLabel(mode),
                        summary = if (settings.colorMode == mode) "当前" else null,
                    ) { scope.launch { container.settingsRepository.setColorMode(mode) } }
                }
            }

            QscSectionLabel("更多")
            QscGroup {
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
