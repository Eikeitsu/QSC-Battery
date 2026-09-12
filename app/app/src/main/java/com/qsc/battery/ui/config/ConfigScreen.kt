package com.qsc.battery.ui.config

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.CurrentConfig
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeChoiceRow
import com.qsc.battery.ui.design.charge.ChargeChipGroup
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeEditSheet
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePresets
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeSkeletonBox
import com.qsc.battery.ui.design.charge.ChargeStickyActionBar
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import com.qsc.battery.ui.design.charge.ChargeTopBar
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
    var stopSchedules by remember { mutableStateOf<List<String>>(emptyList()) }
    var quietSchedules by remember { mutableStateOf<List<String>>(emptyList()) }
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
            val (stop, quiet) = container.configRepository.loadSchedules()
            stopSchedules = stop
            quietSchedules = quiet
        }
        ready = true
    }

    LaunchedEffect(Unit) { reload() }

    val notifyKinds = v("notify_charge_kinds")
        .split(',')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .toSet()
        .ifEmpty { setOf("stop", "resume", "fail") }

    val showSave = ready && rootOk && moduleOk

    // 顶栏 + 可滚动正文 + 底部保存条占位（不叠在列表上）
    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(
            title = if (advancedOnly) "进阶策略" else "策略",
            subtitle = if (advancedOnly) null else "常用项一屏搞定，细节放进阶",
            onBack = onBack,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
                .padding(bottom = ChargeTheme.dimens.bottomBarContentGap),
            verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
        ) {
            when {
                !ready -> {
                    ChargeSkeletonBox(height = 120.dp)
                    ChargeSkeletonBox(height = 80.dp)
                }
                !rootOk -> ChargeBanner("需要 Root 才能修改配置", BannerTone.Warn)
                !moduleOk -> ChargeBanner("模块未安装", BannerTone.Warn)
                !advancedOnly -> {
                    ChargeSection(title = "电量停充") {
                        ChargeChoiceRow(
                            title = "停止充电",
                            chips = ChargePresets.powerStop,
                            selectedId = v("power_stop").ifBlank { null },
                            onSelect = { setLocal("power_stop", it) },
                            onCustom = {
                                edit = EditField("停止充电电量", "%", true, 1, { v("power_stop") }) {
                                    setLocal("power_stop", it)
                                }
                            },
                        )
                        ChargeDivider()
                        ChargeChoiceRow(
                            title = "恢复充电",
                            chips = ChargePresets.powerStart,
                            selectedId = v("power_start").ifBlank { null },
                            onSelect = { setLocal("power_start", it) },
                            onCustom = {
                                edit = EditField("恢复充电电量", "%", true, 1, { v("power_start") }) {
                                    setLocal("power_start", it)
                                }
                            },
                        )
                        ChargeDivider()
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
                        ChargeChoiceRow(
                            title = "停充温度",
                            chips = ChargePresets.tempStop,
                            selectedId = v("temperature_switch_stop").ifBlank { null },
                            onSelect = { setLocal("temperature_switch_stop", it) },
                            onCustom = {
                                edit = EditField("停充温度", "°C", true, 1, { v("temperature_switch_stop") }) {
                                    setLocal("temperature_switch_stop", it)
                                }
                            },
                        )
                        ChargeDivider()
                        ChargeChoiceRow(
                            title = "恢复温度",
                            chips = ChargePresets.tempStart,
                            selectedId = v("temperature_switch_start").ifBlank { null },
                            onSelect = { setLocal("temperature_switch_start", it) },
                            onCustom = {
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
                }
                else -> {
                    ChargeSection(title = "停充行为") {
                        ChargeChoiceRow(
                            title = "停充后保持唤醒锁",
                            chips = ChargePresets.wakeLock,
                            selectedId = v("stop_hold_wakelock").ifBlank { "auto" },
                            summary = "自动：仅在需要时持锁，减少发热",
                            onSelect = { setLocal("stop_hold_wakelock", it) },
                        )
                        ChargeDivider()
                        ChargeChoiceRow(
                            title = "无线充电策略",
                            chips = ChargePresets.wireless,
                            selectedId = v("wireless_policy").ifBlank { "same" },
                            onSelect = { setLocal("wireless_policy", it) },
                        )
                    }

                    ChargeSection(title = "通知与行为") {
                        ChargeToggleRow("充电事件通知", v("notify_charge_event") == "1") {
                            setLocal("notify_charge_event", if (it) "1" else "0")
                        }
                        ChargeToggleRow("常显功耗通知", v("notify_power_status") == "1") {
                            setLocal("notify_power_status", if (it) "1" else "0")
                        }
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text(
                                text = "通知种类",
                                style = ChargeTheme.typography.body,
                                color = ChargeTheme.colors.ink,
                            )
                            ChargeChipGroup(
                                chips = ChargePresets.notifyKinds,
                                selectedId = null,
                                onSelect = {},
                                multiSelect = true,
                                selectedIds = notifyKinds,
                                onToggle = { id ->
                                    val next = notifyKinds.toMutableSet()
                                    if (id in next) next.remove(id) else next.add(id)
                                    setLocal(
                                        "notify_charge_kinds",
                                        next.ifEmpty { setOf("stop") }.joinToString(","),
                                    )
                                },
                            )
                        }
                        ChargeToggleRow("按 App 停充", v("app_stop") == "1") {
                            setLocal("app_stop", if (it) "1" else "0")
                        }
                        ChargeListRow(
                            title = "App 停充列表",
                            summary = v("app_stop_list").ifBlank { "空 · 包名用逗号分隔" },
                            onClick = {
                                edit = EditField("App 停充列表", "", false, null, { v("app_stop_list") }) {
                                    setLocal("app_stop_list", it)
                                }
                            },
                        )
                    }

                    ChargeSection(title = "日程摘要") {
                        ChargeListRow(
                            title = "停充时段",
                            summary = if (stopSchedules.isEmpty()) "未配置" else stopSchedules.joinToString("；"),
                        )
                        ChargeListRow(
                            title = "免打扰通知时段",
                            summary = if (quietSchedules.isEmpty()) "未配置" else quietSchedules.joinToString("；"),
                        )
                        Text(
                            text = "完整日程编辑请用模块 WebUI；此处仅展示。",
                            style = ChargeTheme.typography.caption,
                            color = ChargeTheme.colors.muted,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }

                    ChargeSection(title = "循环与省电") {
                        ChargeToggleRow("省电模式", v("power_saver") == "1") {
                            setLocal("power_saver", if (it) "1" else "0")
                        }
                        ChargeToggleRow("记录充放电历史", v("history_enable") == "1") {
                            setLocal("history_enable", if (it) "1" else "0")
                        }
                        ChargeToggleRow("首页显示曲线（WebUI）", v("chart_show") == "1") {
                            setLocal("chart_show", if (it) "1" else "0")
                        }
                        listOf(
                            Triple("近阈值间隔", "loop_interval_sec", "秒"),
                            Triple("维持间隔", "loop_interval_maintain_sec", "秒"),
                            Triple("未插电间隔", "loop_interval_idle_sec", "秒"),
                            Triple("插电远阈值", "loop_interval_plugged_sec", "秒"),
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
                        ChargeChoiceRow(
                            title = "默认限流",
                            chips = ChargePresets.currentA,
                            selectedId = current.default_current_max_limit.toString(),
                            summary = String.format("%.1f A", current.default_current_max_limit / 1_000_000.0),
                            onSelect = {
                                current = current.copy(
                                    default_current_max_limit = it.toLongOrNull()
                                        ?: current.default_current_max_limit,
                                )
                            },
                            onCustom = {
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
                        ChargeChoiceRow(
                            title = "实现偏好",
                            chips = ChargePresets.nativeImpl,
                            selectedId = v("native_impl").ifBlank { "rust" },
                            onSelect = { setLocal("native_impl", it) },
                        )
                        ChargeListRow(title = "守护状态", summary = daemonStatus.ifBlank { "未知" })
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            ChargeSecondaryButton(
                                text = "检查守护更新",
                                equalHeight = true,
                                onClick = {
                                    scope.launch {
                                        val msg = container.daemonRepository.check()
                                        daemonStatus = container.daemonRepository.status()
                                        snackbar.showSnackbar(msg)
                                    }
                                },
                            )
                            ChargeSecondaryButton(
                                text = "下载并安装守护",
                                equalHeight = true,
                                onClick = {
                                    scope.launch {
                                        val msg = container.daemonRepository.install(
                                            v("native_impl").ifBlank { "rust" },
                                        )
                                        daemonStatus = container.daemonRepository.status()
                                        snackbar.showSnackbar(msg)
                                    }
                                },
                            )
                        }
                    }
                }
            }
        }

        if (showSave) {
            ChargeStickyActionBar(clearSystemNav = advancedOnly) {
                ChargePrimaryButton(
                    text = if (advancedOnly) "保存进阶项" else "保存",
                    onClick = {
                        scope.launch {
                            val okConf = container.configRepository.setConfValues(conf)
                            val okCur = container.configRepository.saveCurrent(current)
                            snackbar.showSnackbar(
                                if (okConf && okCur) {
                                    if (advancedOnly) "已保存" else "已保存，下一轮循环生效"
                                } else {
                                    "保存失败"
                                },
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
