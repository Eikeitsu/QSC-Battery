package com.qsc.battery.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.moriafly.salt.ui.ItemOuterTitle
import com.moriafly.salt.ui.ItemSwitcher
import com.moriafly.salt.ui.ItemValue
import com.moriafly.salt.ui.RoundedColumn
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text
import com.moriafly.salt.ui.UnstableSaltUiApi
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.StatusBundle
import com.qsc.battery.ui.design.AppHeroBattery
import com.qsc.battery.ui.design.AppMetricStrip
import com.qsc.battery.ui.design.AppPage
import com.qsc.battery.ui.design.AppPrimaryButton
import com.qsc.battery.ui.design.VoltBanner
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

@OptIn(UnstableSaltUiApi::class)
@Composable
fun HomeScreen(container: AppContainer) {
    var status by remember { mutableStateOf(StatusBundle()) }
    var loading by remember { mutableStateOf(true) }
    var conf by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        loading = true
        status = container.statusRepository.load()
        if (status.modulePresent) conf = container.configRepository.loadConf()
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

    AppPage(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        Text(
            text = "充电控制",
            style = SaltTheme.textStyles.main,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = status.description.ifBlank { "模块负责停充，本应用负责配置与状态" },
            style = SaltTheme.textStyles.sub,
            color = SaltTheme.colors.subText,
        )

        when {
            !status.rootOk -> VoltBanner("需要 Root：可先改主题；安装/控制模块需要授权 Root")
            !status.modulePresent -> {
                VoltBanner("未检测到模块。可在「我的 → 更新」下载安装。")
                RoundedColumn {
                    Box(modifier = Modifier.padding(16.dp)) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(text = "本应用可单独使用主题与更新检查。")
                            Text(
                                text = "刷入 Magisk「充电控制」后，概览页即可开关与查看电池。",
                                color = SaltTheme.colors.subText,
                                style = SaltTheme.textStyles.sub,
                            )
                        }
                    }
                }
            }
            else -> {
                AppHeroBattery(
                    levelText = levelText,
                    percent = levelPct,
                    statusLine = statusLine,
                    subtitle = status.version.ifBlank { "模块已就绪" },
                )

                RoundedColumn {
                    ItemSwitcher(
                        state = !status.moduleOff,
                        onChange = { enabled ->
                            scope.launch {
                                container.statusRepository.setModuleEnabled(enabled)
                                refresh()
                            }
                        },
                        text = "启用充电控制",
                        sub = if (status.moduleOff) "当前已关闭（off_qsc）" else "模块运行中",
                    )
                }

                ItemOuterTitle(text = "实时数据")
                if (loading) {
                    CircularProgressIndicator(color = SaltTheme.colors.highlight)
                } else {
                    AppMetricStrip(
                        listOf(
                            "温度" to formatTemp(status.snapshot.temp),
                            "电流" to formatUa(status.current),
                            "电压" to formatUv(status.voltage),
                        ),
                    )
                }

                ItemOuterTitle(text = "策略摘要")
                RoundedColumn {
                    ItemValue(text = "停充 / 恢复", sub = "${conf["power_stop"] ?: "--"}% / ${conf["power_start"] ?: "--"}%")
                    ItemValue(
                        text = "温控",
                        sub = "${if (conf["temperature_switch"] == "1") "开" else "关"} · " +
                            "${conf["temperature_switch_stop"] ?: "--"}°C / ${conf["temperature_switch_start"] ?: "--"}°C",
                    )
                    ItemValue(
                        text = "守护",
                        sub = "${if (conf["native_daemon"] == "1") "开" else "关"} · ${conf["native_impl"] ?: "rust"}",
                    )
                    if (status.failed) {
                        ItemValue(text = "提示", sub = "存在停充失败，请检查节点")
                    }
                }

                AppPrimaryButton(
                    text = "刷新",
                    onClick = { scope.launch { refresh() } },
                    modifier = Modifier.fillMaxWidth(),
                )
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
