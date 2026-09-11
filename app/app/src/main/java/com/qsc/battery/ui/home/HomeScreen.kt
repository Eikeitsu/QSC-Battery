package com.qsc.battery.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.StatusBundle
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeHero
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargeMetricRow
import com.qsc.battery.ui.design.charge.ChargePage
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

@Composable
fun HomeScreen(
    container: AppContainer,
    onOpenStrategy: () -> Unit,
) {
    var status by remember { mutableStateOf(StatusBundle()) }
    var loading by remember { mutableStateOf(true) }
    var conf by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    suspend fun refresh(full: Boolean = true) {
        if (full) loading = true
        status = container.statusRepository.load()
        if (status.modulePresent) conf = container.configRepository.loadConf()
        loading = false
    }

    DisposableEffect(lifecycleOwner) {
        var pollJob: Job? = null
        val obs = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    pollJob?.cancel()
                    pollJob = scope.launch {
                        refresh()
                        while (isActive) {
                            delay(8_000)
                            status = container.statusRepository.load()
                        }
                    }
                }
                Lifecycle.Event.ON_PAUSE -> pollJob?.cancel()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose {
            pollJob?.cancel()
            lifecycleOwner.lifecycle.removeObserver(obs)
        }
    }

    val levelRaw = status.snapshot.level
    val levelPct = levelRaw.toFloatOrNull()?.div(100f)
    val levelText = if (levelRaw.isBlank()) "--%" else "${levelRaw}%"
    val statusLine = buildString {
        append(if (status.snapshot.powered) "已插电" else "未插电")
        append(" · ")
        append(status.snapshot.status.ifBlank { "未知" })
        if (status.chargingStopped) append(" · 停充中")
    }

    ChargePage(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Bottom,
        ) {
            Column {
                Text(
                    text = "充电控制",
                    style = ChargeTheme.typography.title,
                    color = ChargeTheme.colors.ink,
                )
                Text(
                    text = "状态一目了然",
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.muted,
                )
            }
            Text(
                text = "刷新",
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clickable { scope.launch { refresh() } },
            )
        }

        when {
            !status.rootOk -> ChargeBanner("需要 Root 才能读写模块配置；主题与更新仍可用。", BannerTone.Warn)
            !status.modulePresent -> {
                ChargeBanner("未检测到 Magisk 模块。可在「我的 → 更新」下载安装。", BannerTone.Info)
                ChargeSection(title = "下一步") {
                    ChargeListRow(
                        title = "安装充电控制模块",
                        summary = "安装后即可在此启停与查看电池",
                        onClick = onOpenStrategy,
                    )
                }
            }
            else -> {
                ChargeHero(
                    levelText = levelText,
                    percent = levelPct,
                    statusLine = statusLine,
                    subtitle = status.version.ifBlank { "模块已就绪" },
                )

                ChargeSection {
                    ChargeToggleRow(
                        title = "充电控制",
                        summary = if (status.moduleOff) "已关闭（off_qsc）" else "模块运行中",
                        checked = !status.moduleOff,
                        onCheckedChange = { enabled ->
                            scope.launch {
                                container.statusRepository.setModuleEnabled(enabled)
                                refresh(full = false)
                            }
                        },
                    )
                }

                if (loading) {
                    CircularProgressIndicator(color = ChargeTheme.colors.accent)
                } else {
                    ChargeMetricRow(
                        listOf(
                            "温度" to formatTemp(status.snapshot.temp),
                            "电流" to formatUa(status.current),
                            "电压" to formatUv(status.voltage),
                        ),
                    )
                }

                ChargeSection(title = "策略摘要") {
                    ChargeListRow(
                        title = "停充 / 恢复",
                        value = "${conf["power_stop"] ?: "--"}% · ${conf["power_start"] ?: "--"}%",
                        onClick = onOpenStrategy,
                    )
                    ChargeListRow(
                        title = "温控",
                        value = if (conf["temperature_switch"] == "1") {
                            "${conf["temperature_switch_stop"] ?: "--"}°C"
                        } else {
                            "关"
                        },
                        onClick = onOpenStrategy,
                    )
                    if (status.failed) {
                        ChargeListRow(
                            title = "提示",
                            summary = "存在停充失败记录，请检查节点",
                        )
                    }
                }
            }
        }
    }
}

private fun formatTemp(raw: String): String {
    val n = raw.toIntOrNull() ?: return raw.ifBlank { "--" }
    val c = if (n > 200) n / 10.0 else n.toDouble()
    return String.format("%.1f°C", c)
}

private fun formatUv(raw: String): String {
    val n = raw.toLongOrNull() ?: return raw.ifBlank { "--" }
    return String.format("%.2f V", n / 1_000_000.0)
}

private fun formatUa(raw: String): String {
    val n = raw.toLongOrNull() ?: return raw.ifBlank { "--" }
    return String.format("%.0f mA", n / 1000.0)
}
