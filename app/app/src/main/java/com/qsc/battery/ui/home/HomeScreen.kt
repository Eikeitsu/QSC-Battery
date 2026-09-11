package com.qsc.battery.ui.home

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.StatusBundle
import com.qsc.battery.ui.components.PrefSwitch
import com.qsc.battery.ui.components.QscBody
import com.qsc.battery.ui.components.QscGroup
import com.qsc.battery.ui.components.QscHeroBattery
import com.qsc.battery.ui.components.QscMetricGrid
import com.qsc.battery.ui.components.QscPage
import com.qsc.battery.ui.components.QscSectionLabel
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

    val levelRaw = status.snapshot.level
    val levelPct = levelRaw.toFloatOrNull()?.div(100f)
    val levelText = if (levelRaw.isBlank()) "--%" else "${levelRaw}%"
    val statusLine = buildString {
        append(if (status.snapshot.powered) "已插电" else "未插电")
        append(" · ")
        append(status.snapshot.status.ifBlank { "未知" })
        if (status.chargingStopped) append(" · 停充中")
    }

    QscPage(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text("充电控制", style = MaterialTheme.typography.headlineSmall)
        Text(
            status.description.ifBlank { "模块负责停充，本应用负责配置与状态" },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        when {
            !status.rootOk -> StatusBanner(
                text = "需要 Root：可先改主题；安装/控制模块需要授权 Root",
            )
            !status.modulePresent -> {
                StatusBanner(
                    text = "未检测到模块。可在「更多 → 更新」下载安装；装上后才能停充。",
                )
                QscGroup {
                    QscBody(spacedBy = 8.dp) {
                        Text("本应用可单独使用主题与更新检查。", style = MaterialTheme.typography.bodyMedium)
                        Text(
                            "刷入 Magisk「充电控制」模块后，主页即可开关与查看电池。",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            else -> {
                QscHeroBattery(
                    levelText = levelText,
                    percent = levelPct,
                    subtitle = status.version.ifBlank { "模块已就绪" },
                    statusLine = statusLine,
                )

                QscGroup {
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

                QscSectionLabel("电池详情")
                QscGroup {
                    if (loading) {
                        QscBody { CircularProgressIndicator() }
                    } else {
                        QscMetricGrid(
                            listOf(
                                "温度" to formatTemp(status.snapshot.temp),
                                "电压" to formatUv(status.voltage),
                                "电流" to formatUa(status.current),
                                "停充" to if (status.chargingStopped) "是" else "否",
                                "供电" to if (status.snapshot.powered) "已插电" else "未插电",
                                "版本" to status.version.ifBlank { "--" },
                            ),
                        )
                        QscBody {
                            Button(onClick = { scope.launch { refresh() } }, modifier = Modifier.fillMaxWidth()) {
                                Text("刷新")
                            }
                        }
                    }
                }

                QscSectionLabel("策略摘要")
                QscGroup {
                    QscBody(spacedBy = 6.dp) {
                        Text("停充 ${conf["power_stop"] ?: "--"}% · 恢复 ${conf["power_start"] ?: "--"}%")
                        Text(
                            "温控 ${if (conf["temperature_switch"] == "1") "开" else "关"} · " +
                                "${conf["temperature_switch_stop"] ?: "--"}°C / ${conf["temperature_switch_start"] ?: "--"}°C",
                        )
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
