package com.qsc.battery.ui.more

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.ui.theme.PaletteStyleName
import com.qsc.battery.ui.theme.ThemeSettings
import kotlinx.coroutines.launch

private fun paletteStyleLabel(style: PaletteStyleName): String = when (style) {
    PaletteStyleName.TonalSpot -> "色调点缀"
    PaletteStyleName.Neutral -> "中性"
    PaletteStyleName.Vibrant -> "鲜艳"
    PaletteStyleName.Expressive -> "表现力"
    PaletteStyleName.Rainbow -> "彩虹"
    PaletteStyleName.FruitSalad -> "果色"
    PaletteStyleName.Monochrome -> "单色"
    PaletteStyleName.Fidelity -> "保真"
    PaletteStyleName.Content -> "内容"
}

@Composable
fun ColorPaletteScreen(
    container: AppContainer,
    onBack: () -> Unit,
) {
    val settings by container.settingsRepository.settings.collectAsStateWithLifecycle(
        initialValue = ThemeSettings(),
    )
    val scope = rememberCoroutineScope()
    val colors = listOf(
        0xFF0B6E4F, 0xFF12B886, 0xFF006A6A, 0xFF1B6EF3, 0xFF8B5000,
        0xFFB3261E, 0xFF006E1C, 0xFF6750A4, 0xFF7A5900, 0xFF006877,
    )

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(title = "调色板", onBack = onBack)
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
            ChargeSection(title = "种子色") {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(56.dp),
                    contentPadding = PaddingValues(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.size(width = 360.dp, height = 140.dp),
                ) {
                    items(colors) { c ->
                        val selected = settings.keyColor == c.toInt()
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .clip(CircleShape)
                                .background(Color(c))
                                .then(
                                    if (selected) Modifier.border(3.dp, Color.White, CircleShape)
                                    else Modifier,
                                )
                                .clickable {
                                    scope.launch { container.settingsRepository.setKeyColor(c.toInt()) }
                                },
                        )
                    }
                }
            }

            ChargeSection(title = "配色风格") {
                PaletteStyleName.entries.forEachIndexed { index, style ->
                    if (index > 0) ChargeDivider()
                    ChargeListRow(
                        title = paletteStyleLabel(style),
                        summary = style.wire,
                        value = if (settings.paletteStyle == style) "已选" else null,
                        onClick = {
                            scope.launch { container.settingsRepository.setPaletteStyle(style) }
                        },
                    )
                }
            }

            ChargeSection(title = "色规") {
                listOf("SPEC_2021" to "2021", "SPEC_2025" to "2025").forEachIndexed { index, (spec, label) ->
                    if (index > 0) ChargeDivider()
                    ChargeListRow(
                        title = label,
                        value = if (settings.colorSpec == spec) "已选" else null,
                        onClick = {
                            scope.launch { container.settingsRepository.setColorSpec(spec) }
                        },
                    )
                }
            }
        }
    }
}
