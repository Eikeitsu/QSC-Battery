package com.qsc.battery.ui.log

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.ChargeEvent
import com.qsc.battery.data.model.LogLine
import com.qsc.battery.ui.design.VoltChipRow
import com.qsc.battery.ui.design.VoltPage
import com.qsc.battery.ui.design.VoltSection
import com.qsc.battery.ui.design.VoltSectionLabel
import kotlinx.coroutines.launch

private enum class LogTab { Runtime, Events }
private enum class ViewMode { Flat, Session }

@Composable
fun LogScreen(container: AppContainer) {
    var tab by remember { mutableStateOf(LogTab.Runtime) }
    var level by remember { mutableStateOf("") }
    var viewMode by remember { mutableStateOf(ViewMode.Flat) }
    var lines by remember { mutableStateOf<List<LogLine>>(emptyList()) }
    var events by remember { mutableStateOf<List<ChargeEvent>>(emptyList()) }
    var historyPreview by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        lines = container.logRepository.loadLogTail()
        events = container.logRepository.loadEvents()
        historyPreview = container.logRepository.loadHistoryCsv(40)
    }

    LaunchedEffect(Unit) { refresh() }

    VoltPage(modifier = Modifier.fillMaxSize()) {
        Text("日志", style = MaterialTheme.typography.headlineSmall)
        VoltChipRow(
            options = listOf(
                "运行日志" to (tab == LogTab.Runtime),
                "充电事件" to (tab == LogTab.Events),
            ),
            onSelect = { tab = if (it == 0) LogTab.Runtime else LogTab.Events },
        )

        if (tab == LogTab.Runtime) {
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                VoltChipRow(
                    options = listOf(
                        "全部" to (level == ""),
                        "信息" to (level == "info"),
                        "警告" to (level == "warn"),
                        "错误" to (level == "error"),
                        "调试" to (level == "debug"),
                    ),
                    onSelect = { idx ->
                        level = listOf("", "info", "warn", "error", "debug")[idx]
                    },
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                VoltChipRow(
                    options = listOf(
                        "平铺" to (viewMode == ViewMode.Flat),
                        "会话" to (viewMode == ViewMode.Session),
                    ),
                    onSelect = { viewMode = if (it == 0) ViewMode.Flat else ViewMode.Session },
                )
                TextButton(onClick = { scope.launch { refresh() } }) { Text("刷新") }
                TextButton(onClick = { scope.launch { container.logRepository.clearLog(); refresh() } }) { Text("清空") }
            }

            val filtered = lines.filter { level.isEmpty() || it.level == level }
            VoltSection(modifier = Modifier.weight(1f, fill = true)) {
                if (viewMode == ViewMode.Session) {
                    val sessions = groupSessions(filtered)
                    LazyColumn(modifier = Modifier.padding(12.dp)) {
                        for ((title, body) in sessions) {
                            item {
                                Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(vertical = 6.dp))
                            }
                            items(body) { LogText(it) }
                        }
                    }
                } else {
                    LazyColumn(modifier = Modifier.padding(12.dp)) {
                        items(filtered) { LogText(it) }
                    }
                }
            }

            if (historyPreview.isNotBlank()) {
                VoltSectionLabel("充电历史片段")
                VoltSection {
                    Text(
                        historyPreview.take(1200),
                        modifier = Modifier.padding(12.dp),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { scope.launch { refresh() } }) { Text("刷新") }
                TextButton(onClick = { scope.launch { container.logRepository.clearEvents(); refresh() } }) { Text("清空") }
            }
            VoltSection(modifier = Modifier.weight(1f, fill = true)) {
                LazyColumn(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(events) { e ->
                        Column {
                            Text("${e.dateText} ${e.timeText} · ${e.type}", style = MaterialTheme.typography.titleSmall)
                            Text(
                                buildString {
                                    e.level?.let { append("电量 $it%  ") }
                                    e.temp?.let { append("温度 $it°C  ") }
                                    append(e.detail)
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LogText(line: LogLine) {
    val color = when (line.level) {
        "error" -> MaterialTheme.colorScheme.error
        "warn" -> MaterialTheme.colorScheme.tertiary
        "debug" -> MaterialTheme.colorScheme.onSurfaceVariant
        else -> MaterialTheme.colorScheme.onSurface
    }
    Text(line.raw, color = color, fontFamily = FontFamily.Monospace, fontSize = 11.sp, modifier = Modifier.padding(vertical = 2.dp))
}

private fun groupSessions(lines: List<LogLine>): List<Pair<String, List<LogLine>>> {
    if (lines.isEmpty()) return emptyList()
    val sessions = mutableListOf<Pair<String, MutableList<LogLine>>>()
    var currentTitle = "会话"
    var bucket = mutableListOf<LogLine>()
    fun flush() {
        if (bucket.isNotEmpty()) sessions += currentTitle to bucket
        bucket = mutableListOf()
    }
    lines.forEach { line ->
        val raw = line.raw
        when {
            raw.contains("停止充电", true) || raw.contains("CHARGE_STOP", true) -> {
                flush()
                currentTitle = "停充 · ${raw.take(48)}"
                bucket += line
            }
            raw.contains("恢复充电", true) || raw.contains("CHARGE_START", true) -> {
                bucket += line
                flush()
                currentTitle = "已恢复"
            }
            else -> bucket += line
        }
    }
    flush()
    return sessions
}
