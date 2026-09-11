package com.qsc.battery.ui.more

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
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
import com.moriafly.salt.ui.ItemCheck
import com.moriafly.salt.ui.ItemOuterTitle
import com.moriafly.salt.ui.RoundedColumn
import com.moriafly.salt.ui.UnstableSaltUiApi
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.AppPage
import com.qsc.battery.ui.design.AppTitleBar
import com.qsc.battery.ui.theme.PaletteStyleName
import com.qsc.battery.ui.theme.ThemeSettings
import kotlinx.coroutines.launch

@OptIn(UnstableSaltUiApi::class)
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
        Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        AppTitleBar(title = "调色板", onBack = onBack)
        AppPage(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            includeStatusSpacer = false,
        ) {
            ItemOuterTitle(text = "种子色")
            LazyVerticalGrid(
                columns = GridCells.Adaptive(56.dp),
                contentPadding = PaddingValues(8.dp),
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

            ItemOuterTitle(text = "PaletteStyle")
            RoundedColumn {
                PaletteStyleName.entries.forEach { style ->
                    ItemCheck(
                        state = settings.paletteStyle == style,
                        onChange = {
                            if (it) scope.launch { container.settingsRepository.setPaletteStyle(style) }
                        },
                        text = style.wire,
                    )
                }
            }

            ItemOuterTitle(text = "ColorSpec")
            RoundedColumn {
                listOf("SPEC_2021", "SPEC_2025").forEach { spec ->
                    ItemCheck(
                        state = settings.colorSpec == spec,
                        onChange = {
                            if (it) scope.launch { container.settingsRepository.setColorSpec(spec) }
                        },
                        text = spec.removePrefix("SPEC_"),
                    )
                }
            }
        }
    }
}
