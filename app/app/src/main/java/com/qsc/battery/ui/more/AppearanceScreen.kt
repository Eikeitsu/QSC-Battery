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
import androidx.compose.ui.Modifier.modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.components.PrefAction
import com.qsc.battery.ui.components.PrefCard
import com.qsc.battery.ui.components.PrefSwitch
import com.qsc.battery.ui.components.SectionLabel
import com.qsc.battery.ui.theme.ColorMode
import com.qsc.battery.ui.theme.LocalUiMode
import com.qsc.battery.ui.theme.ThemeSettings
import com.qsc.battery.ui.theme.UiMode
import kotlinx.coroutines.launch
import top.yukonga.miuix.kmp.extra.SuperArrow
import top.yukonga.miuix.kmp.extra.SuperSwitch

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
            if (LocalUiMode.current == UiMode.Miuix) {
                AppearanceMiuix(
                    settings = settings,
                    onUiMode = { scope.launch { container.settingsRepository.setUiMode(it) } },
                    onColorMode = { scope.launch { container.settingsRepository.setColorMode(it) } },
                    onMiuixMonet = { scope.launch { container.settingsRepository.setMiuixMonet(it) } },
                    onAltIcon = { scope.launch { container.settingsRepository.setAlternativeIcon(it) } },
                    onOpenPalette = onOpenPalette,
                )
            } else {
                AppearanceMaterial(
                    settings = settings,
                    onUiMode = { scope.launch { container.settingsRepository.setUiMode(it) } },
                    onColorMode = { scope.launch { container.settingsRepository.setColorMode(it) } },
                    onMiuixMonet = { scope.launch { container.settingsRepository.setMiuixMonet(it) } },
                    onAltIcon = { scope.launch { container.settingsRepository.setAlternativeIcon(it) } },
                    onOpenPalette = onOpenPalette,
                )
            }
        }
    }
}

@Composable
private fun AppearanceMiuix(
    settings: ThemeSettings,
    onUiMode: (UiMode) -> Unit,
    onColorMode: (ColorMode) -> Unit,
    onMiuixMonet: (Boolean) -> Unit,
    onAltIcon: (Boolean) -> Unit,
    onOpenPalette: () -> Unit,
) {
    SectionLabel("界面风格")
    PrefCard {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("MIUIX / Material Design 3", style = MaterialTheme.typography.bodySmall)
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = settings.uiMode == UiMode.Miuix,
                    onClick = { onUiMode(UiMode.Miuix) },
                    shape = SegmentedButtonDefaults.itemShape(0, 2),
                ) { Text("MIUIX") }
                SegmentedButton(
                    selected = settings.uiMode == UiMode.Material,
                    onClick = { onUiMode(UiMode.Material) },
                    shape = SegmentedButtonDefaults.itemShape(1, 2),
                ) { Text("Material") }
            }
        }
        ColorMode.entries.forEach { mode ->
            SuperArrow(
                title = modeLabel(mode),
                summary = if (settings.colorMode == mode) "当前" else null,
                onClick = { onColorMode(mode) },
            )
        }
        SuperSwitch(
            title = "MIUIX 跟随动态取色",
            summary = "开启后 MIUIX 风格也使用动态取色",
            checked = settings.miuixMonet,
            onCheckedChange = onMiuixMonet,
        )
        SuperArrow(title = "调色板", summary = "keyColor / PaletteStyle / ColorSpec", onClick = onOpenPalette)
        SuperSwitch(
            title = "备用桌面图标",
            summary = "切换启动器图标",
            checked = settings.alternativeIcon,
            onCheckedChange = onAltIcon,
        )
    }
}

@Composable
private fun AppearanceMaterial(
    settings: ThemeSettings,
    onUiMode: (UiMode) -> Unit,
    onColorMode: (ColorMode) -> Unit,
    onMiuixMonet: (Boolean) -> Unit,
    onAltIcon: (Boolean) -> Unit,
    onOpenPalette: () -> Unit,
) {
    SectionLabel("界面风格")
    PrefCard {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("在 MIUIX 与 Material Design 3 之间切换", style = MaterialTheme.typography.bodySmall)
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = settings.uiMode == UiMode.Miuix,
                    onClick = { onUiMode(UiMode.Miuix) },
                    shape = SegmentedButtonDefaults.itemShape(0, 2),
                ) { Text("MIUIX") }
                SegmentedButton(
                    selected = settings.uiMode == UiMode.Material,
                    onClick = { onUiMode(UiMode.Material) },
                    shape = SegmentedButtonDefaults.itemShape(1, 2),
                ) { Text("Material") }
            }
        }
    }
    SectionLabel("颜色模式")
    PrefCard {
        ColorMode.entries.forEach { mode ->
            PrefAction(
                title = modeLabel(mode),
                summary = if (settings.colorMode == mode) "当前" else null,
            ) { onColorMode(mode) }
        }
    }
    if (settings.uiMode == UiMode.Miuix) {
        PrefCard {
            PrefSwitch(
                title = "MIUIX 跟随动态取色",
                summary = "开启后 MIUIX 风格也使用动态取色",
                checked = settings.miuixMonet,
                onCheckedChange = onMiuixMonet,
            )
        }
    }
    PrefCard {
        PrefAction("调色板", "keyColor / PaletteStyle / ColorSpec", onClick = onOpenPalette)
        PrefSwitch(
            title = "备用桌面图标",
            summary = "切换启动器图标",
            checked = settings.alternativeIcon,
            onCheckedChange = onAltIcon,
        )
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
