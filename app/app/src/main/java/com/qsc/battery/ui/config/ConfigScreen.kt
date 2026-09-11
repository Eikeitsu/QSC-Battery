package com.qsc.battery.ui.config

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.CurrentConfig
import com.qsc.battery.ui.design.PrefSwitch
import com.qsc.battery.ui.design.VoltBanner
import com.qsc.battery.ui.design.VoltPage
import com.qsc.battery.ui.design.VoltPrimaryButton
import com.qsc.battery.ui.design.VoltSection
import com.qsc.battery.ui.design.VoltSectionLabel
import kotlinx.coroutines.launch

@Composable
fun ConfigScreen(container: AppContainer) {
    var conf by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var current by remember { mutableStateOf(CurrentConfig()) }
    var message by remember { mutableStateOf<String?>(null) }
    var ready by remember { mutableStateOf(false) }
    var rootOk by remember { mutableStateOf(false) }
    var moduleOk by remember { mutableStateOf(false) }
    var daemonStatus by remember { mutableStateOf("") }
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

    VoltPage(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text("策略", style = MaterialTheme.typography.headlineSmall)
        message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }

        if (!ready) {
            Text("加载中…")
            return@VoltPage
        }
        if (!rootOk) {
            VoltBanner("需要 Root 才能修改配置")
            return@VoltPage
        }
        if (!moduleOk) {
            VoltBanner("模块未安装")
            return@VoltPage
        }

        VoltSectionLabel("电量停充")
        VoltSection {
            NumberField("停止充电电量 (%)", v("power_stop")) { setLocal("power_stop", it) }
            NumberField("恢复充电电量 (%)", v("power_start")) { setLocal("power_start", it) }
            NumberField("延时停充 (秒)", v("power_stop_time")) { setLocal("power_stop_time", it) }
            PrefSwitch("充满再停", v("charge_full") == "1") { setLocal("charge_full", if (it) "1" else "0") }
            PrefSwitch("自动拔插", v("power_reset") == "1") { setLocal("power_reset", if (it) "1" else "0") }
            PrefSwitch("兼容模式", v("Compatibility_mode") == "1") {
                setLocal("Compatibility_mode", if (it) "1" else "0")
            }
        }

        VoltSectionLabel("温度")
        VoltSection {
            PrefSwitch("温度停充", v("temperature_switch") == "1") {
                setLocal("temperature_switch", if (it) "1" else "0")
            }
            NumberField("停充温度 (°C)", v("temperature_switch_stop")) {
                setLocal("temperature_switch_stop", it)
            }
            NumberField("恢复温度 (°C)", v("temperature_switch_start")) {
                setLocal("temperature_switch_start", it)
            }
        }

        VoltSectionLabel("通知与行为")
        VoltSection {
            PrefSwitch("充电事件通知", v("notify_charge_event") == "1") {
                setLocal("notify_charge_event", if (it) "1" else "0")
            }
            PrefSwitch("常显功耗通知", v("notify_power_status") == "1") {
                setLocal("notify_power_status", if (it) "1" else "0")
            }
            TextField("通知种类", v("notify_charge_kinds")) { setLocal("notify_charge_kinds", it) }
            TextField("停充持锁", v("stop_hold_wakelock")) { setLocal("stop_hold_wakelock", it) }
            PrefSwitch("按 App 停充", v("app_stop") == "1") { setLocal("app_stop", if (it) "1" else "0") }
            TextField("App 停充列表", v("app_stop_list")) { setLocal("app_stop_list", it) }
        }

        VoltSectionLabel("循环与省电")
        VoltSection {
            PrefSwitch("省电模式", v("power_saver") == "1") { setLocal("power_saver", if (it) "1" else "0") }
            NumberField("近阈值间隔 (秒)", v("loop_interval_sec")) { setLocal("loop_interval_sec", it) }
            NumberField("维持间隔 (秒)", v("loop_interval_maintain_sec")) {
                setLocal("loop_interval_maintain_sec", it)
            }
            NumberField("未插电间隔", v("loop_interval_idle_sec")) { setLocal("loop_interval_idle_sec", it) }
            NumberField("未插电(守护)", v("loop_interval_idle_native_sec")) {
                setLocal("loop_interval_idle_native_sec", it)
            }
            NumberField("插电远阈值", v("loop_interval_plugged_sec")) {
                setLocal("loop_interval_plugged_sec", it)
            }
            NumberField("插电远阈值(守护)", v("loop_interval_plugged_native_sec")) {
                setLocal("loop_interval_plugged_native_sec", it)
            }
            NumberField("近窗口 (%)", v("loop_interval_near_window")) {
                setLocal("loop_interval_near_window", it)
            }
            TextField("无线策略", v("wireless_policy")) { setLocal("wireless_policy", it) }
            PrefSwitch("充放电历史", v("history_enable") == "1") {
                setLocal("history_enable", if (it) "1" else "0")
            }
            PrefSwitch("主页曲线", v("chart_show") == "1") { setLocal("chart_show", if (it) "1" else "0") }
        }

        VoltSectionLabel("电流控制")
        VoltSection {
            PrefSwitch("启用电流控制", current.current_control == 1) {
                current = current.copy(current_control = if (it) 1 else 0)
            }
            PrefSwitch("旁路充电", current.bypass_enable == 1) {
                current = current.copy(bypass_enable = if (it) 1 else 0)
            }
            PrefSwitch("温度限流", current.temperature_current == 1) {
                current = current.copy(temperature_current = if (it) 1 else 0)
            }
            PrefSwitch("按 App 限流", current.app_limit == 1) {
                current = current.copy(app_limit = if (it) 1 else 0)
            }
            NumberField("安全温度上限", current.safety_temp_max.toString()) {
                current = current.copy(safety_temp_max = it.toIntOrNull() ?: current.safety_temp_max)
            }
            NumberField("默认限流 (uA)", current.default_current_max_limit.toString()) {
                current = current.copy(
                    default_current_max_limit = it.toLongOrNull() ?: current.default_current_max_limit,
                )
            }
        }

        VoltSectionLabel("事件唤醒守护")
        VoltSection {
            PrefSwitch("启用守护", v("native_daemon") == "1") {
                setLocal("native_daemon", if (it) "1" else "0")
            }
            TextField("实现偏好 (rust/c/off)", v("native_impl")) { setLocal("native_impl", it) }
            Text(
                daemonStatus.ifBlank { "状态未知" },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                style = MaterialTheme.typography.bodySmall,
            )
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                VoltPrimaryButton("检查更新", onClick = {
                    scope.launch {
                        message = container.daemonRepository.check()
                        daemonStatus = container.daemonRepository.status()
                    }
                })
                VoltPrimaryButton("下载并安装守护", onClick = {
                    scope.launch {
                        message = container.daemonRepository.install(v("native_impl").ifBlank { "rust" })
                        daemonStatus = container.daemonRepository.status()
                    }
                })
                VoltPrimaryButton("移除守护", onClick = {
                    scope.launch {
                        message = container.daemonRepository.remove()
                        daemonStatus = container.daemonRepository.status()
                    }
                })
            }
        }

        VoltPrimaryButton(
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

@Composable
private fun NumberField(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
    )
}

@Composable
private fun TextField(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        singleLine = true,
    )
}
