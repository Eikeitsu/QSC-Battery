package com.qsc.battery.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.AppViewModelFactory
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeHero
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargeMetricRow
import com.qsc.battery.ui.design.charge.ChargeMetricSkeleton
import com.qsc.battery.ui.design.charge.ChargeScreen
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.ui.design.charge.batteryStatusLabel
import com.qsc.battery.ui.design.charge.isActivelyCharging
import com.qsc.battery.ui.util.LifecycleResumePollEffect

@Composable
fun HomeScreen(
    container: AppContainer,
    onOpenStrategy: () -> Unit,
) {
    val factory = remember(container) { AppViewModelFactory(container) }
    val vm: HomeViewModel = viewModel(factory = factory)
    val ui by vm.ui.collectAsStateWithLifecycle()

    LifecycleResumePollEffect(intervalMs = 8_000) { first ->
        vm.refresh(full = first)
    }

    val status = ui.status
    val conf = ui.conf
    val levelRaw = status.snapshot.level
    val levelPct = levelRaw.toFloatOrNull()?.div(100f)
    val levelText = if (levelRaw.isBlank()) "--%" else "${levelRaw}%"
    val chargeLabel = batteryStatusLabel(
        status.snapshot.status,
        powered = status.snapshot.powered,
        stopped = status.chargingStopped,
    )
    val statusLine = buildString {
        append(if (status.snapshot.powered) "已插电" else "未插电")
        append(" · ")
        append(chargeLabel)
        if (status.chargingStopped) append(" · 停充中")
    }
    val charging = isActivelyCharging(
        status.snapshot.status,
        status.snapshot.powered,
        status.chargingStopped,
    )

    ChargeScreen(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            ChargeTopBar(
                title = "充电控制",
                subtitle = "状态一目了然",
                actions = {
                    Text(
                        text = "刷新",
                        style = ChargeTheme.typography.label,
                        color = ChargeTheme.colors.accent,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.clickable { vm.refreshAsync(full = true) },
                    )
                },
            )
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
        ) {
            when {
                !ui.bootstrapped -> ChargeMetricSkeleton()
                ui.rootSettled && !status.rootOk -> {
                    ChargeBanner("需要 Root 才能读写模块配置；主题与更新仍可用。", BannerTone.Warn)
                }
                ui.rootSettled && !status.modulePresent -> {
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
                        charging = charging,
                    )

                    ChargeSection {
                        ChargeToggleRow(
                            title = "充电控制",
                            summary = if (status.moduleOff) "已关闭" else "模块运行中",
                            checked = !status.moduleOff,
                            onCheckedChange = { enabled -> vm.setModuleEnabled(enabled) },
                        )
                    }

                    ChargeMetricRow(
                        listOf(
                            "温度" to formatTemp(status.snapshot.temp),
                            "电流" to formatUa(status.current),
                            "电压" to formatUv(status.voltage),
                        ),
                    )

                    ChargeSection(title = "常用策略") {
                        ChargeListRow(
                            title = "停充 / 恢复",
                            value = "${conf["power_stop"] ?: "--"}% → ${conf["power_start"] ?: "--"}%",
                            onClick = onOpenStrategy,
                        )
                        ChargeListRow(
                            title = "温度停充",
                            summary = if (conf["temperature_switch"] == "1") {
                                "${conf["temperature_switch_stop"] ?: "--"}°C / ${conf["temperature_switch_start"] ?: "--"}°C"
                            } else {
                                "未启用"
                            },
                            onClick = onOpenStrategy,
                        )
                    }
                }
            }
        }
    }
}

private fun formatTemp(raw: String): String {
    val t = raw.toFloatOrNull() ?: return "--"
    val c = if (t > 200) t / 10f else t
    return String.format("%.1f°C", c)
}

private fun formatUa(raw: String): String {
    val ua = raw.toLongOrNull() ?: return "--"
    val a = kotlin.math.abs(ua) / 1_000_000.0
    return String.format("%s%.2fA", if (ua < 0) "-" else "", a)
}

private fun formatUv(raw: String): String {
    val uv = raw.toLongOrNull() ?: return "--"
    return String.format("%.2fV", uv / 1_000_000.0)
}
