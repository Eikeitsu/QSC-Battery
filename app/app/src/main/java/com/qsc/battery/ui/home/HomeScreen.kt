package com.qsc.battery.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.StatusBundle
import com.qsc.battery.ui.components.PrefBody
import com.qsc.battery.ui.components.PrefCard
import com.qsc.battery.ui.components.PrefSwitch
import com.qsc.battery.ui.components.SectionLabel
import com.qsc.battery.ui.components.StatusBanner
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

@Composable
fun HomeScreen(container: AppContainer) {
    var status by remember { mutableStateOf(StatusBundle()) }
    var loading by remember { mutableStateOf(true) }
    var conf by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        loading = true
        status = container.statusRepository.load()
        if (status.modulePresent) {
            conf = container.configRepository.loadConf()
        }
        loading = false
    }

    LaunchedEffect(Unit) {
        refresh()
        while (isActive) {
            delay(8_000)
            status = container.statusRepository.load()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("QSC Battery", style = MaterialTheme.typography.headlineSmall)
        Text(
            status.description.ifBlank { "充电控制伴侣" },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        when {
            !status.rootOk -> StatusBanner(
                text = "需要 Root：可先改主题；安装/控制模块需要授权 Root",
            )
            !status.modulePresent -> {
                StatusBanner(
                    text = "未检测到 QSC_Battery 模块。APP 可单独使用（主题/检查更新）；停充需安装模块。请到「更多 → 更新」下载安装。",
                )
                PrefCard {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("模块可选：本 APP 不依赖模块也能打开。", style = MaterialTheme.typography.bodyMedium)
                        Text("装上模块后即可在本页开关停充与查看电池状态。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            else -> {
                PrefCard {
                    PrefSwitch(
                        title = "启用充电控制",
                        summary = if (status.moduleOff) "当前已关闭（off_qsc）" else "模块运行中",
                        checked = !status.moduleOff,
                        onCheckedChange = { enabled ->
                            scope.launch {
                                container.statusRepository.setModuleEnabled(enabled)
                                refresh()
                            }
                        },
                    )
                }

                SectionLabel("电池")
                PrefCard {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (loading) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                                CircularProgressIndicator()
                            }
                        } else {
                            Metric("电量", "${status.snapshot.level.ifBlank { "--" }}%")
                            Metric("温度", formatTemp(status.snapshot.temp))
                            Metric("状态", status.snapshot.status.ifBlank { "--" })
                            Metric("供电", if (status.snapshot.powered) "已插电" else "未插电")
                            Metric("停充中", if (status.chargingStopped) "是" else "否")
                            Metric("电压", formatUv(status.voltage))
                            Metric("电流", formatUa(status.current))
                            Metric("模块版本", status.version.ifBlank { "--" })
                        }
                        Spacer(Modifier.height(4.dp))
                        Button(onClick = { scope.launch { refresh() } }, modifier = Modifier.fillMaxWidth()) {
                            Text("刷新")
                        }
                    }
                }

                SectionLabel("策略摘要")
                PrefCard {
                    PrefBody(spacedBy = 6.dp) {
                        Text("停充 ${conf["power_stop"] ?: "--"}% · 恢复 ${conf["power_start"] ?: "--"}%")
                        Text("温控 ${if (conf["temperature_switch"] == "1") "开" else "关"} · ${conf["temperature_switch_stop"] ?: "--"}°C / ${conf["temperature_switch_start"] ?: "--"}°C")
                        Text("守护 ${if (conf["native_daemon"] == "1") "开" else "关"} · ${conf["native_impl"] ?: "rust"}")
                        if (status.failed) {
                            Text("存在停充失败提示，请检查节点", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Metric(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleMedium)
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
