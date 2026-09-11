package com.qsc.battery.ui.config

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.moriafly.salt.ui.Item
import com.moriafly.salt.ui.ItemArrowType
import com.moriafly.salt.ui.ItemOuterTitle
import com.moriafly.salt.ui.ItemSwitcher
import com.moriafly.salt.ui.RoundedColumn
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text
import com.moriafly.salt.ui.UnstableSaltUiApi
import com.moriafly.salt.ui.dialog.InputDialog
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.CurrentConfig
import com.qsc.battery.ui.design.AppPage
import com.qsc.battery.ui.design.AppPrimaryButton
import com.qsc.battery.ui.design.AppSecondaryButton
import com.qsc.battery.ui.design.VoltBanner
import kotlinx.coroutines.launch

private sealed class EditTarget {
    data class Conf(val key: String, val title: String, val numeric: Boolean) : EditTarget()
    data class CurrentInt(val title: String, val getter: (CurrentConfig) -> String, val setter: (CurrentConfig, String) -> CurrentConfig) : EditTarget()
    data class CurrentLong(val title: String, val getter: (CurrentConfig) -> String, val setter: (CurrentConfig, String) -> CurrentConfig) : EditTarget()
}

@OptIn(UnstableSaltUiApi::class)
@Composable
fun ConfigScreen(container: AppContainer) {
    var conf by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var current by remember { mutableStateOf(CurrentConfig()) }
    var message by remember { mutableStateOf<String?>(null) }
    var ready by remember { mutableStateOf(false) }
    var rootOk by remember { mutableStateOf(false) }
    var moduleOk by remember { mutableStateOf(false) }
    var daemonStatus by remember { mutableStateOf("") }
    var edit by remember { mutableStateOf<EditTarget?>(null) }
    var draft by remember { mutableStateOf("") }
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

    fun openConf(key: String, title: String, numeric: Boolean = true) {
        draft = v(key)
        edit = EditTarget.Conf(key, title, numeric)
    }

    AppPage(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        Text(
            text = "策略",
            style = SaltTheme.textStyles.main,
            fontWeight = FontWeight.SemiBold,
        )
        message?.let {
            Text(text = it, color = SaltTheme.colors.highlight, style = SaltTheme.textStyles.sub)
        }

        if (!ready) {
            Text(text = "加载中…", color = SaltTheme.colors.subText)
            return@AppPage
        }
        if (!rootOk) {
            VoltBanner("需要 Root 才能修改配置")
            return@AppPage
        }
        if (!moduleOk) {
            VoltBanner("模块未安装")
            return@AppPage
        }

        ItemOuterTitle(text = "电量停充")
        RoundedColumn {
            ValueItem("停止充电电量", "${v("power_stop").ifBlank { "--" }}%") {
                openConf("power_stop", "停止充电电量 (%)")
            }
            ValueItem("恢复充电电量", "${v("power_start").ifBlank { "--" }}%") {
                openConf("power_start", "恢复充电电量 (%)")
            }
            ValueItem("延时停充", "${v("power_stop_time").ifBlank { "--" }} 秒") {
                openConf("power_stop_time", "延时停充 (秒)")
            }
            ItemSwitcher(
                state = v("charge_full") == "1",
                onChange = { setLocal("charge_full", if (it) "1" else "0") },
                text = "充满再停",
            )
            ItemSwitcher(
                state = v("power_reset") == "1",
                onChange = { setLocal("power_reset", if (it) "1" else "0") },
                text = "自动拔插",
            )
            ItemSwitcher(
                state = v("Compatibility_mode") == "1",
                onChange = { setLocal("Compatibility_mode", if (it) "1" else "0") },
                text = "兼容模式",
            )
        }

        ItemOuterTitle(text = "温度")
        RoundedColumn {
            ItemSwitcher(
                state = v("temperature_switch") == "1",
                onChange = { setLocal("temperature_switch", if (it) "1" else "0") },
                text = "温度停充",
            )
            ValueItem("停充温度", "${v("temperature_switch_stop").ifBlank { "--" }}°C") {
                openConf("temperature_switch_stop", "停充温度 (°C)")
            }
            ValueItem("恢复温度", "${v("temperature_switch_start").ifBlank { "--" }}°C") {
                openConf("temperature_switch_start", "恢复温度 (°C)")
            }
        }

        ItemOuterTitle(text = "通知与行为")
        RoundedColumn {
            ItemSwitcher(
                state = v("notify_charge_event") == "1",
                onChange = { setLocal("notify_charge_event", if (it) "1" else "0") },
                text = "充电事件通知",
            )
            ItemSwitcher(
                state = v("notify_power_status") == "1",
                onChange = { setLocal("notify_power_status", if (it) "1" else "0") },
                text = "常显功耗通知",
            )
            ValueItem("通知种类", v("notify_charge_kinds").ifBlank { "未设置" }) {
                openConf("notify_charge_kinds", "通知种类", numeric = false)
            }
            ValueItem("停充持锁", v("stop_hold_wakelock").ifBlank { "未设置" }) {
                openConf("stop_hold_wakelock", "停充持锁", numeric = false)
            }
            ItemSwitcher(
                state = v("app_stop") == "1",
                onChange = { setLocal("app_stop", if (it) "1" else "0") },
                text = "按 App 停充",
            )
            ValueItem("App 停充列表", v("app_stop_list").ifBlank { "空" }) {
                openConf("app_stop_list", "App 停充列表", numeric = false)
            }
        }

        ItemOuterTitle(text = "循环与省电")
        RoundedColumn {
            ItemSwitcher(
                state = v("power_saver") == "1",
                onChange = { setLocal("power_saver", if (it) "1" else "0") },
                text = "省电模式",
            )
            ValueItem("近阈值间隔", "${v("loop_interval_sec").ifBlank { "--" }} 秒") {
                openConf("loop_interval_sec", "近阈值间隔 (秒)")
            }
            ValueItem("维持间隔", "${v("loop_interval_maintain_sec").ifBlank { "--" }} 秒") {
                openConf("loop_interval_maintain_sec", "维持间隔 (秒)")
            }
            ValueItem("未插电间隔", v("loop_interval_idle_sec").ifBlank { "--" }) {
                openConf("loop_interval_idle_sec", "未插电间隔")
            }
            ValueItem("未插电(守护)", v("loop_interval_idle_native_sec").ifBlank { "--" }) {
                openConf("loop_interval_idle_native_sec", "未插电间隔(守护)")
            }
            ValueItem("插电远阈值", v("loop_interval_plugged_sec").ifBlank { "--" }) {
                openConf("loop_interval_plugged_sec", "插电远阈值")
            }
            ValueItem("插电远阈值(守护)", v("loop_interval_plugged_native_sec").ifBlank { "--" }) {
                openConf("loop_interval_plugged_native_sec", "插电远阈值(守护)")
            }
            ValueItem("近窗口", "${v("loop_interval_near_window").ifBlank { "--" }}%") {
                openConf("loop_interval_near_window", "近窗口 (%)")
            }
            ValueItem("无线策略", v("wireless_policy").ifBlank { "未设置" }) {
                openConf("wireless_policy", "无线策略", numeric = false)
            }
            ItemSwitcher(
                state = v("history_enable") == "1",
                onChange = { setLocal("history_enable", if (it) "1" else "0") },
                text = "充放电历史",
            )
            ItemSwitcher(
                state = v("chart_show") == "1",
                onChange = { setLocal("chart_show", if (it) "1" else "0") },
                text = "主页曲线",
            )
        }

        ItemOuterTitle(text = "电流控制")
        RoundedColumn {
            ItemSwitcher(
                state = current.current_control == 1,
                onChange = { current = current.copy(current_control = if (it) 1 else 0) },
                text = "启用电流控制",
            )
            ItemSwitcher(
                state = current.bypass_enable == 1,
                onChange = { current = current.copy(bypass_enable = if (it) 1 else 0) },
                text = "旁路充电",
            )
            ItemSwitcher(
                state = current.temperature_current == 1,
                onChange = { current = current.copy(temperature_current = if (it) 1 else 0) },
                text = "温度限流",
            )
            ItemSwitcher(
                state = current.app_limit == 1,
                onChange = { current = current.copy(app_limit = if (it) 1 else 0) },
                text = "按 App 限流",
            )
            ValueItem("安全温度上限", current.safety_temp_max.toString()) {
                draft = current.safety_temp_max.toString()
                edit = EditTarget.CurrentInt(
                    title = "安全温度上限",
                    getter = { it.safety_temp_max.toString() },
                    setter = { c, s -> c.copy(safety_temp_max = s.toIntOrNull() ?: c.safety_temp_max) },
                )
            }
            ValueItem("默认限流 (uA)", current.default_current_max_limit.toString()) {
                draft = current.default_current_max_limit.toString()
                edit = EditTarget.CurrentLong(
                    title = "默认限流 (uA)",
                    getter = { it.default_current_max_limit.toString() },
                    setter = { c, s ->
                        c.copy(default_current_max_limit = s.toLongOrNull() ?: c.default_current_max_limit)
                    },
                )
            }
        }

        ItemOuterTitle(text = "事件唤醒守护")
        RoundedColumn {
            ItemSwitcher(
                state = v("native_daemon") == "1",
                onChange = { setLocal("native_daemon", if (it) "1" else "0") },
                text = "启用守护",
            )
            ValueItem("实现偏好", v("native_impl").ifBlank { "rust" }) {
                openConf("native_impl", "实现偏好 (rust/c/off)", numeric = false)
            }
            ValueItem("守护状态", daemonStatus.ifBlank { "状态未知" }, clickable = false)
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            AppSecondaryButton(
                text = "检查守护更新",
                onClick = {
                    scope.launch {
                        message = container.daemonRepository.check()
                        daemonStatus = container.daemonRepository.status()
                    }
                },
            )
            AppSecondaryButton(
                text = "下载并安装守护",
                onClick = {
                    scope.launch {
                        message = container.daemonRepository.install(v("native_impl").ifBlank { "rust" })
                        daemonStatus = container.daemonRepository.status()
                    }
                },
            )
            AppSecondaryButton(
                text = "移除守护",
                onClick = {
                    scope.launch {
                        message = container.daemonRepository.remove()
                        daemonStatus = container.daemonRepository.status()
                    }
                },
            )
            AppPrimaryButton(
                text = "保存全部",
                onClick = {
                    scope.launch {
                        val okConf = container.configRepository.setConfValues(conf)
                        val okCur = container.configRepository.saveCurrent(current)
                        message = if (okConf && okCur) "已保存（下一轮循环生效）" else "保存失败"
                    }
                },
            )
        }
    }

    val target = edit
    if (target != null) {
        InputDialog(
            onDismissRequest = { edit = null },
            onConfirm = {
                when (val t = target) {
                    is EditTarget.Conf -> setLocal(t.key, draft.trim())
                    is EditTarget.CurrentInt -> current = t.setter(current, draft.trim())
                    is EditTarget.CurrentLong -> current = t.setter(current, draft.trim())
                }
                edit = null
            },
            title = when (target) {
                is EditTarget.Conf -> target.title
                is EditTarget.CurrentInt -> target.title
                is EditTarget.CurrentLong -> target.title
            },
            text = draft,
            onChange = { draft = it },
            hint = "输入新值",
        )
    }
}

@OptIn(UnstableSaltUiApi::class)
@Composable
private fun ValueItem(
    title: String,
    value: String,
    clickable: Boolean = true,
    onClick: () -> Unit = {},
) {
    Item(
        onClick = onClick,
        text = title,
        tag = value,
        arrowType = if (clickable) ItemArrowType.Arrow else ItemArrowType.None,
        enabled = clickable,
    )
}
