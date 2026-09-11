package com.qsc.battery.ui.log

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.ChargeEvent
import com.qsc.battery.data.model.LogLine
import com.qsc.battery.ui.design.charge.ChargePage
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeSegmented
import com.qsc.battery.ui.design.charge.ChargeTheme
import kotlinx.coroutines.launch

private enum class LogTab { Runtime, Events }

@Composable
fun LogScreen(container: AppContainer) {
    var tab by remember { mutableStateOf(LogTab.Runtime) }
    var level by remember { mutableStateOf("") }
    var lines by remember { mutableStateOf<List<LogLine>>(emptyList()) }
    var events by remember { mutableStateOf<List<ChargeEvent>>(emptyList()) }
    var filterOpen by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        lines = container.logRepository.loadLogTail()
        events = container.logRepository.loadEvents()
    }

    LaunchedEffect(Unit) { refresh() }

    Column(modifier = Modifier.fillMaxSize()) {
        ChargePage(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(
                        text = "动态",
                        style = ChargeTheme.typography.title,
                        color = ChargeTheme.colors.ink,
                    )
                    Text(
                        text = "运行日志与充电事件",
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.muted,
                    )
                }
                Box {
                    Text(
                        text = "筛选",
                        color = ChargeTheme.colors.accent,
                        style = ChargeTheme.typography.label,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .clickable { filterOpen = true }
                            .padding(8.dp),
                    )
                    DropdownMenu(expanded = filterOpen, onDismissRequest = { filterOpen = false }) {
                        listOf(
                            "" to "全部",
                            "info" to "信息",
                            "warn" to "警告",
                            "error" to "错误",
                            "debug" to "调试",
                        ).forEach { (key, label) ->
                            DropdownMenuItem(
                                text = { Text(label) },
                                onClick = {
                                    level = key
                                    filterOpen = false
                                },
                            )
                        }
                    }
                }
            }

            ChargeSegmented(
                options = listOf("运行", "事件"),
                selectedIndex = if (tab == LogTab.Runtime) 0 else 1,
                onSelect = { tab = if (it == 0) LogTab.Runtime else LogTab.Events },
            )

            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                ChargeSecondaryButton(
                    text = "刷新",
                    onClick = { scope.launch { refresh() } },
                    modifier = Modifier.weight(1f),
                )
                ChargeSecondaryButton(
                    text = "清空",
                    onClick = {
                        scope.launch {
                            if (tab == LogTab.Runtime) container.logRepository.clearLog()
                            else container.logRepository.clearEvents()
                            refresh()
                        }
                    },
                    modifier = Modifier.weight(1f),
                )
            }
        }

        if (tab == LogTab.Runtime) {
            val filtered = lines.filter { level.isEmpty() || it.level == level }
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                items(filtered) { line ->
                    val color = when (line.level) {
                        "error" -> ChargeTheme.colors.danger
                        "warn" -> ChargeTheme.colors.accent
                        "debug" -> ChargeTheme.colors.muted
                        else -> ChargeTheme.colors.ink
                    }
                    Text(text = line.raw, style = ChargeTheme.typography.mono, color = color)
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(events) { e ->
                    Column {
                        Text(
                            text = "${e.dateText} ${e.timeText} · ${e.type}",
                            style = ChargeTheme.typography.label,
                            color = ChargeTheme.colors.ink,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = buildString {
                                e.level?.let { append("电量 $it%  ") }
                                e.temp?.let { append("温度 $it°C  ") }
                                append(e.detail)
                            },
                            style = ChargeTheme.typography.caption,
                            color = ChargeTheme.colors.muted,
                        )
                    }
                }
            }
        }
    }
}
