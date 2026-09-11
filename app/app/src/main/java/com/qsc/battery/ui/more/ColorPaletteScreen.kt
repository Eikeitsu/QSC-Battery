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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier.modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.components.SectionLabel
import com.qsc.battery.ui.theme.PaletteStyleName
import com.qsc.battery.ui.theme.ThemeSettings
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
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
        0xFF0B6E4F, 0xFF6750A4, 0xFF006A6A, 0xFF8B5000, 0xFFB3261E,
        0xFF1B6EF3, 0xFF006E1C, 0xFF9C4146, 0xFF7A5900, 0xFF006877,
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("调色板") },
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
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionLabel("种子色")
            LazyVerticalGrid(
                columns = GridCells.Adaptive(56.dp),
                contentPadding = PaddingValues(8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f, fill = false),
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

            SectionLabel("PaletteStyle")
            PaletteStyleName.entries.chunked(3).forEach { row ->
                androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { style ->
                        FilterChip(
                            selected = settings.paletteStyle == style,
                            onClick = { scope.launch { container.settingsRepository.setPaletteStyle(style) } },
                            label = { Text(style.wire) },
                        )
                    }
                }
            }

            SectionLabel("ColorSpec")
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("SPEC_2021", "SPEC_2025").forEach { spec ->
                    FilterChip(
                        selected = settings.colorSpec == spec,
                        onClick = { scope.launch { container.settingsRepository.setColorSpec(spec) } },
                        label = { Text(spec.removePrefix("SPEC_")) },
                    )
                }
            }
        }
    }
}
