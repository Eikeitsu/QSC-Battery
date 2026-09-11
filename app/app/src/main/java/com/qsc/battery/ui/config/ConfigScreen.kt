package com.qsc.battery.ui.config

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.SnackbarHostState
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
import com.qsc.battery.data.model.CurrentConfig
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeEditSheet
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePage
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTitleBar
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import kotlinx.coroutines.launch

private data class EditField(
    val title: String,
    val unit: String,
    val numeric: Boolean,
    val step: Int?,
    val get: () -> String,
    val set: (String) -> Unit,
)

@Composable
fun ConfigScreen(
    container: AppContainer,
    snackbar: SnackbarHostState,
    advancedOnly: Boolean = false,
    onOpenAdvanced: (() -> Unit)? = null,
    onBack: (() -> Unit)? = null,
) {
    var conf by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var current by remember { mutableStateOf(CurrentConfig()) }
    var ready by remember { mutableStateOf(false) }
    var rootOk by remember { mutableStateOf(false) }
    var moduleOk by remember { mutableStateOf(false) }
    var daemonStatus by remember { mutableStateOf("") }
    var edit by remember { mutableStateOf<EditField?>(null) }
    val scope = rememberCoroutineScope()

    fun v(key: String) = conf[key].orEmpty()
    fun setLocal(key: String, value: String) {
        conf = conf.toMutableMap().apply { put(key, value) }
    }

    suspend fun reload() {
        rootOk = container.root.isRootAvailable()
        val st = container.statusRepository.load()
        moduleOk = st.modulePresent
        if (moduleOk) {
            conf = container.configRepository.loadConf()
            current = container.configRepository.loadCurrent()
            daemonStatus = container.daemonRepository.status()
        }
        ready = true
    }

    LaunchedEffect(Unit) { reload() }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = if (!advancedOnly) 88.dp else 24.dp),
        ) {
            ChargePage(includeStatusSpacer = onBack == null) {
                if (onBack != null) {
                    ChargeTitleBar(title = if (advancedOnly) "进阶策略" else "策略", onBack = onBack)
                } else {
                    Text(
                        text = "策略",
                        style = ChargeTheme.typography.title,
                        color = ChargeTheme.colors.ink,
                    )
                    Text(
                        text = "常用项一屏搞定，细节放进阶",
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.muted,
                    )
                }

                if (!ready) {
                    Text("加载中…", color = ChargeTheme.colors.muted, style = ChargeTheme.typography.body)
                    return@ChargePage
                }
                if (!rootOk) {
                    ChargeBanner("需要 Root 才能修改配置", BannerTone.Warn)
                    return@ChargePage
                }
                if (!moduleOk) {
                    ChargeBanner("模块未安装", BannerTone.Warn)
                    return@ChargePage
                }

                if (!advancedOnly) {
                    ChargeSection(title = "电量停充") {
                        ChargeListRow(
                            title = "停止充电",
                            value = "${v("power_stop").ifBlank { "--" }} %",
                            onClick = {
                                edit = EditField("停止充电电量", "%", true, 1, { v("power_stop") }) {
                                    setLocal("power_stop", it)
                                }
                            },
                        )
                        ChargeListRow(
                            title = "恢复充电",
                            value = "${v("power_start").ifBlank { "--" }} %",
                            onClick = {
                                edit = EditField("恢复充电电量", "%", true, 1, { v("power_start") }) {
                                    setLocal("power_start", it)
                                }
                            },
                        )
                        ChargeListRow(
                            title = "延时停充",
                            value = "${v("power_stop_time").ifBlank { "--" }} 秒",
                            onClick = {
                                edit = EditField("延时停充", "秒", true, 1, { v("power_stop_time") }) {
                                    setLocal("power_stop_time", it)
                                }
                            },
                        )
                        ChargeToggleRow("充满再停", v("charge_full") == "1") {
                            setLocal("charge_full", if (it) "1" else "0")
                        }
                        ChargeToggleRow("自动拔插", v("power_reset") == "1") {
                            setLocal("power_reset", if (it) "1" else "0")
                        }
                        ChargeToggleRow("兼容模式", v("Compatibility_mode") == "1") {
                            setLocal("Compatibility_mode", if (it) "1" else "0")
                        }
                    }

                    ChargeSection(title = "温度") {
                        ChargeToggleRow("温度停充", v("temperature_switch") == "1") {
                            setLocal("temperature_switch", if (it) "1" else "0")
                        }
                        ChargeListRow(
                            title = "停充温度",
                            value = "${v("temperature_switch_stop").ifBlank { "--" }} °C",
                            onClick = {
                                edit = EditField("停充温度", "°C", true, 1, { v("temperature_switch_stop") }) {
                                    setLocal("temperature_switch_stop", it)
                                }
                            },
                        )
                        ChargeListRow(
                            title = "恢复温度",
                            value = "${v("temperature_switch_start").ifBlank { "--" }} °C",
                            onClick = {
                                edit = EditField("恢复温度", "°C", true, 1, { v("temperature_switch_start") }) {
                                    setLocal("temperature_switch_start", it)
                                }
                            },
                        )
                    }

                    ChargeSection(title = "更多") {
                        ChargeListRow(
                            title = "进阶策略",
                            summary = "循环间隔、电流控制、守护与通知",
                            onClick = { onOpenAdvanced?.invoke() },
                        )
                    }
                } else {
                    ChargeSection(title = "通知与行为") {
                        ChargeToggleRow("充电事件通知", v("notify_charge_event") == "1") {
                            setLocal("notify_charge_event", if (it) "1" else "0")
                        }
                        ChargeToggleRow("常显功耗通知", v("notify_power_status") == "1") {
                            setLocal("notify_power_status", if (it) "1" else "0")
                        }
                        ChargeListRow(
                            title = "通知种类",
                            value = v("notify_charge_kinds").ifBlank { "默认" },
                            onClick = {
                                edit = EditField("通知种类", "", false, null, { v("notify_charge_kinds") }) {
                                    setLocal("notify_charge_kinds", it)
                                }
                            },
                        )
                        ChargeToggleRow("按 App 停充", v("app_stop") == "1") {
                            setLocal("app_stop", if (it) "1" else "0")
                        }
                        ChargeListRow(
                            title = "App 停充列表",
                            summary = v("app_stop_list").ifBlank { "空" },
                            onClick = {
                                edit = EditField("App 停充列表", "", false, null, { v("app_stop_list") }) {
                                    setLocal("app_stop_list", it)
                                }
                            },
                        )
                    }

                    ChargeSection(title = "循环与省电") {
                        ChargeToggleRow("省电模式", v("power_saver") == "1") {
                            setLocal("power_saver", if (it) "1" else "0")
                        }
                        listOf(
                            Triple("近阈值间隔", "loop_interval_sec", "秒"),
                            Triple("维持间隔", "loop_interval_maintain_sec", "秒"),
                            Triple("未插电间隔", "loop_interval_idle_sec", "秒"),
                            Triple("未插电(守护)", "loop_interval_idle_native_sec", "秒"),
                            Triple("插电远阈值", "loop_interval_plugged_sec", "秒"),
                            Triple("插电远阈值(守护)", "loop_interval_plugged_native_sec", "秒"),
                            Triple("近窗口", "loop_interval_near_window", "%"),
                        ).forEach { (title, key, unit) ->
                            ChargeListRow(
                                title = title,
                                value = "${v(key).ifBlank { "--" }} $unit",
                                onClick = {
                                    edit = EditField(title, unit, true, 1, { v(key) }) { setLocal(key, it) }
                                },
                            )
                        }
                        ChargeToggleRow("充放电历史", v("history_enable") == "1") {
                            setLocal("history_enable", if (it) "1" else "0")
                        }
                    }

                    ChargeSection(title = "电流控制") {
                        ChargeToggleRow("启用电流控制", current.current_control == 1) {
                            current = current.copy(current_control = if (it) 1 else 0)
                        }
                        ChargeToggleRow("旁路充电", current.bypass_enable == 1) {
                            current = current.copy(bypass_enable = if (it) 1 else 0)
                        }
                        ChargeToggleRow("温度限流", current.temperature_current == 1) {
                            current = current.copy(temperature_current = if (it) 1 else 0)
                        }
                        ChargeListRow(
                            title = "安全温度上限",
                            value = "${current.safety_temp_max} °C",
                            onClick = {
                                edit = EditField("安全温度上限", "°C", true, 1, {
                                    current.safety_temp_max.toString()
                                }) {
                                    current = current.copy(
                                        safety_temp_max = it.toIntOrNull() ?: current.safety_temp_max,
                                    )
                                }
                            },
                        )
                        ChargeListRow(
                            title = "默认限流",
                            value = String.format("%.1f A", current.default_current_max_limit / 1_000_000.0),
                            summary = "进阶原始值 ${current.default_current_max_limit} µA",
                            onClick = {
                                edit = EditField("默认限流 (µA)", "µA", true, 100_000, {
                                    current.default_current_max_limit.toString()
                                }) {
                                    current = current.copy(
                                        default_current_max_limit = it.toLongOrNull()
                                            ?: current.default_current_max_limit,
                                    )
                                }
                            },
                        )
                    }

                    ChargeSection(title = "事件唤醒守护") {
                        ChargeToggleRow("启用守护", v("native_daemon") == "1") {
                            setLocal("native_daemon", if (it) "1" else "0")
                        }
                        ChargeListRow(
                            title = "实现偏好",
                            value = v("native_impl").ifBlank { "rust" },
                            onClick = {
                                edit = EditField("实现偏好 (rust/c/off)", "", false, null, { v("native_impl") }) {
                                    setLocal("native_impl", it)
                                }
                            },
                        )
                        ChargeListRow(title = "守护状态", summary = daemonStatus.ifBlank { "未知" })
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                        ) {
                            ChargeSecondaryButton("检查守护更新") {
                                scope.launch {
                                    val msg = container.daemonRepository.check()
                                    daemonStatus = container.daemonRepository.status()
                                    snackbar.showSnackbar(msg)
                                }
                            }
                            ChargeSecondaryButton("下载并安装守护") {
                                scope.launch {
                                    val msg = container.daemonRepository.install(v("native_impl").ifBlank { "rust" })
                                    daemonStatus = container.daemonRepository.status()
                                    snackbar.showSnackbar(msg)
                                }
                            }
                        }
                    }
                }
            }
        }

        if (!advancedOnly && ready && rootOk && moduleOk) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .navigationBarsPadding()
                    .padding(bottom = 12.dp),
            ) {
                ChargePrimaryButton(
                    text = "保存",
                    onClick = {
                        scope.launch {
                            val okConf = container.configRepository.setConfValues(conf)
                            val okCur = container.configRepository.saveCurrent(current)
                            snackbar.showSnackbar(
                                if (okConf && okCur) "已保存，下一轮循环生效" else "保存失败",
                            )
                        }
                    },
                )
            }
        } else if (advancedOnly && ready && rootOk && moduleOk) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .navigationBarsPadding()
                    .padding(bottom = 12.dp),
            ) {
                ChargePrimaryButton(
                    text = "保存进阶项",
                    onClick = {
                        scope.launch {
                            val okConf = container.configRepository.setConfValues(conf)
                            val okCur = container.configRepository.saveCurrent(current)
                            snackbar.showSnackbar(
                                if (okConf && okCur) "已保存" else "保存失败",
                            )
                        }
                    },
                )
            }
        }
    }

    val field = edit
    if (field != null) {
        ChargeEditSheet(
            title = field.title,
            value = field.get(),
            unit = field.unit,
            numeric = field.numeric,
            step = field.step,
            onDismiss = { edit = null },
            onConfirm = {
                field.set(it)
                edit = null
            },
        )
    }
}
