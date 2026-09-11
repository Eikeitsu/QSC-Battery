package com.qsc.battery.ui.log

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.moriafly.salt.ui.Item
import com.moriafly.salt.ui.ItemArrowType
import com.moriafly.salt.ui.ItemCheck
import com.moriafly.salt.ui.ItemOuterTitle
import com.moriafly.salt.ui.RoundedColumn
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text
import com.moriafly.salt.ui.UnstableSaltUiApi
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.ChargeEvent
import com.qsc.battery.data.model.LogLine
import com.qsc.battery.ui.design.AppPage
import com.qsc.battery.ui.design.AppPrimaryButton
import com.qsc.battery.ui.design.AppSecondaryButton
import kotlinx.coroutines.launch

private enum class LogTab { Runtime, Events }
private enum class ViewMode { Flat, Session }

@OptIn(UnstableSaltUiApi::class)
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

    AppPage(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        Text(
            text = "日志",
            style = SaltTheme.textStyles.main,
            fontWeight = FontWeight.SemiBold,
        )

        RoundedColumn {
            ItemCheck(
                state = tab == LogTab.Runtime,
                onChange = { if (it) tab = LogTab.Runtime },
                text = "运行日志",
            )
            ItemCheck(
                state = tab == LogTab.Events,
                onChange = { if (it) tab = LogTab.Events },
                text = "充电事件",
            )
        }

        if (tab == LogTab.Runtime) {
            ItemOuterTitle(text = "级别")
            RoundedColumn {
                listOf("" to "全部", "info" to "信息", "warn" to "警告", "error" to "错误", "debug" to "调试")
                    .forEach { (key, label) ->
                        ItemCheck(
                            state = level == key,
                            onChange = { if (it) level = key },
                            text = label,
                        )
                    }
            }

            ItemOuterTitle(text = "视图")
            RoundedColumn {
                ItemCheck(
                    state = viewMode == ViewMode.Flat,
                    onChange = { if (it) viewMode = ViewMode.Flat },
                    text = "平铺",
                )
                ItemCheck(
                    state = viewMode == ViewMode.Session,
                    onChange = { if (it) viewMode = ViewMode.Session },
                    text = "会话",
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AppSecondaryButton(
                    text = "刷新",
                    onClick = { scope.launch { refresh() } },
                    modifier = Modifier.weight(1f),
                )
                AppSecondaryButton(
                    text = "清空",
                    onClick = { scope.launch { container.logRepository.clearLog(); refresh() } },
                    modifier = Modifier.weight(1f),
                )
            }

            val filtered = lines.filter { level.isEmpty() || it.level == level }
            ItemOuterTitle(text = "内容 (${filtered.size})")
            RoundedColumn {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 420.dp)
                        .padding(12.dp)
                        .horizontalScroll(rememberScrollState()),
                ) {
                    if (viewMode == ViewMode.Session) {
                        groupSessions(filtered).forEach { (title, body) ->
                            Text(
                                text = title,
                                style = SaltTheme.textStyles.main,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.padding(vertical = 6.dp),
                            )
                            body.forEach { LogText(it) }
                        }
                    } else {
                        filtered.forEach { LogText(it) }
                    }
                }
            }

            if (historyPreview.isNotBlank()) {
                ItemOuterTitle(text = "充电历史片段")
                RoundedColumn {
                    Text(
                        text = historyPreview.take(1200),
                        modifier = Modifier.padding(12.dp),
                        color = SaltTheme.colors.subText,
                        style = SaltTheme.textStyles.sub,
                        fontFamily = FontFamily.Monospace,
                    )
                }
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AppSecondaryButton(
                    text = "刷新",
                    onClick = { scope.launch { refresh() } },
                    modifier = Modifier.weight(1f),
                )
                AppSecondaryButton(
                    text = "清空",
                    onClick = { scope.launch { container.logRepository.clearEvents(); refresh() } },
                    modifier = Modifier.weight(1f),
                )
            }
            ItemOuterTitle(text = "事件")
            RoundedColumn {
                if (events.isEmpty()) {
                    Item(
                        onClick = {},
                        text = "暂无事件",
                        arrowType = ItemArrowType.None,
                        enabled = false,
                    )
                } else {
                    events.take(80).forEach { e ->
                        Item(
                            onClick = {},
                            text = "${e.dateText} ${e.timeText} · ${e.type}",
                            sub = buildString {
                                e.level?.let { append("电量 $it%  ") }
                                e.temp?.let { append("温度 $it°C  ") }
                                append(e.detail)
                            },
                            arrowType = ItemArrowType.None,
                            enabled = false,
                        )
                    }
                }
            }
        }

        AppPrimaryButton(text = "重新加载", onClick = { scope.launch { refresh() } })
    }
}

@Composable
private fun LogText(line: LogLine) {
    val color = when (line.level) {
        "error" -> Color(0xFFB3261E)
        "warn" -> Color(0xFFE6A700)
        "debug" -> SaltTheme.colors.subText
        else -> SaltTheme.colors.text
    }
    Text(
        text = line.raw,
        color = color,
        fontFamily = FontFamily.Monospace,
        style = SaltTheme.textStyles.sub,
        modifier = Modifier.padding(vertical = 2.dp),
    )
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
