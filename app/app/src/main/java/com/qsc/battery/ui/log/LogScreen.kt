package com.qsc.battery.ui.log

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.ChargeEvent
import com.qsc.battery.data.model.LogLine
import com.qsc.battery.ui.design.charge.ChargeChipGroup
import com.qsc.battery.ui.design.charge.ChargePresets
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeSegmented
import com.qsc.battery.ui.design.charge.ChargeSkeletonBox
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.ui.design.charge.chargeEventTypeLabel
import kotlinx.coroutines.launch

private enum class LogTab { Runtime, Events }

@Composable
fun LogScreen(container: AppContainer) {
    var tab by remember { mutableStateOf(LogTab.Runtime) }
    var level by remember { mutableStateOf("") }
    var lines by remember { mutableStateOf<List<LogLine>>(emptyList()) }
    var events by remember { mutableStateOf<List<ChargeEvent>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        loading = lines.isEmpty() && events.isEmpty()
        lines = container.logRepository.loadLogTail()
        events = container.logRepository.loadEvents()
        loading = false
    }

    LaunchedEffect(Unit) { refresh() }

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(
            title = "动态",
            subtitle = "运行日志与充电事件",
        )

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            stickyHeader {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(ChargeTheme.colors.background)
                        .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
                        .padding(
                            top = ChargeTheme.dimens.topBarContentGap,
                            bottom = 14.dp,
                        ),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    ChargeSegmented(
                        options = listOf("运行", "事件"),
                        selectedIndex = if (tab == LogTab.Runtime) 0 else 1,
                        onSelect = { tab = if (it == 0) LogTab.Runtime else LogTab.Events },
                    )
                    if (tab == LogTab.Runtime) {
                        ChargeChipGroup(
                            chips = ChargePresets.logLevels,
                            selectedId = level,
                            onSelect = { level = it },
                        )
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        ChargeSecondaryButton(
                            text = "刷新",
                            equalHeight = true,
                            modifier = Modifier.weight(1f),
                            onClick = { scope.launch { refresh() } },
                        )
                        ChargeSecondaryButton(
                            text = "清空",
                            equalHeight = true,
                            modifier = Modifier.weight(1f),
                            onClick = {
                                scope.launch {
                                    if (tab == LogTab.Runtime) container.logRepository.clearLog()
                                    else container.logRepository.clearEvents()
                                    refresh()
                                }
                            },
                        )
                    }
                }
            }

            if (loading) {
                item {
                    Column(
                        modifier = Modifier.padding(horizontal = ChargeTheme.dimens.pageHorizontal),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        repeat(4) { ChargeSkeletonBox(height = 48.dp) }
                    }
                }
            } else if (tab == LogTab.Runtime) {
                val filtered = lines.filter { level.isEmpty() || it.level == level }
                if (filtered.isEmpty()) {
                    item {
                        Text(
                            text = "暂无运行日志",
                            style = ChargeTheme.typography.body,
                            color = ChargeTheme.colors.muted,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 24.dp),
                        )
                    }
                } else {
                    items(filtered) { line ->
                        LogRuntimeRow(line)
                    }
                }
            } else {
                if (events.isEmpty()) {
                    item {
                        Text(
                            text = "暂无充电事件",
                            style = ChargeTheme.typography.body,
                            color = ChargeTheme.colors.muted,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 24.dp),
                        )
                    }
                } else {
                    items(events.asReversed()) { e ->
                        EventRow(e)
                    }
                }
            }

            item { Spacer(modifier = Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun LogRuntimeRow(line: LogLine) {
    val color = when (line.level) {
        "error" -> ChargeTheme.colors.danger
        "warn" -> ChargeTheme.colors.accent
        "debug" -> ChargeTheme.colors.muted
        else -> ChargeTheme.colors.ink
    }
    val levelLabel = when (line.level) {
        "error" -> "错误"
        "warn" -> "警告"
        "debug" -> "调试"
        "info" -> "信息"
        else -> line.level.ifBlank { "日志" }
    }
    val time = Regex("""\d{2}:\d{2}:\d{2}""").find(line.raw)?.value.orEmpty()
    val message = line.raw
        .replace(Regex("""^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s*"""), "")
        .replace(Regex("""\[(ERROR|WARN|DEBUG|INFO)\]\s*""", RegexOption.IGNORE_CASE), "")
        .ifBlank { line.raw }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
            .clip(RoundedCornerShape(12.dp))
            .background(ChargeTheme.colors.surface)
            .padding(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(36.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(color),
        )
        Spacer(modifier = Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = levelLabel,
                    style = ChargeTheme.typography.caption,
                    color = color,
                    fontWeight = FontWeight.SemiBold,
                )
                if (time.isNotBlank()) {
                    Text(
                        text = time,
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.muted,
                    )
                }
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = message,
                style = ChargeTheme.typography.body,
                color = ChargeTheme.colors.ink,
            )
        }
    }
}

@Composable
private fun EventRow(e: ChargeEvent) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
            .clip(RoundedCornerShape(12.dp))
            .background(ChargeTheme.colors.surface)
            .padding(14.dp),
    ) {
        Text(
            text = "${e.dateText} ${e.timeText} · ${chargeEventTypeLabel(e.type)}",
            style = ChargeTheme.typography.label,
            color = ChargeTheme.colors.ink,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(4.dp))
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
