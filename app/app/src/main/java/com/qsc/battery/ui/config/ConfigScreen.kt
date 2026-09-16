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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.AppViewModelFactory
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
    val factory = remember(container) { AppViewModelFactory(container) }
    val vm: ConfigViewModel = viewModel(factory = factory)
    val ui by vm.ui.collectAsStateWithLifecycle()
    var edit by remember { mutableStateOf<EditField?>(null) }

    fun v(key: String) = vm.v(key)
    fun setLocal(key: String, value: String) = vm.setLocal(key, value)
    val current = ui.current

    LaunchedEffect(Unit) { vm.reload() }
    LaunchedEffect(ui.lastSaveMessage) {
        ui.lastSaveMessage?.let {
            snackbar.showSnackbar(it)
            vm.consumeSaveMessage()
        }
    }
    LaunchedEffect(ui.lastDaemonMessage) {
        ui.lastDaemonMessage?.let {
            snackbar.showSnackbar(it)
            vm.consumeDaemonMessage()
        }
    }

    val ready = ui.ready
    val rootOk = ui.rootOk
    val moduleOk = ui.moduleOk
    val daemonStatus = ui.daemonStatus
    val stopSchedules = ui.stopSchedules
    val quietSchedules = ui.quietSchedules

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
                .padding(
                    top = ChargeTheme.dimens.pageContentTop,
                    bottom = ChargeTheme.dimens.bottomBarContentGap,
                ),
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
                        ChargeDivider()
                        ChargeToggleRow(
                            title = "全量盲写停充节点",
                            checked = v("switch_batch_blind") != "0",
                            summary = "开=全量写+每轮重申；关=首成功后仅重申",
                            onCheckedChange = {
                                setLocal("switch_batch_blind", if (it) "1" else "0")
                            },
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
                            vm.updateCurrent { c -> c.copy(current_control = if (it) 1 else 0) }
                        }
                        ChargeToggleRow("旁路充电", current.bypass_enable == 1) {
                            vm.updateCurrent { c -> c.copy(bypass_enable = if (it) 1 else 0) }
                        }
                        ChargeToggleRow("温度限流", current.temperature_current == 1) {
                            vm.updateCurrent { c -> c.copy(temperature_current = if (it) 1 else 0) }
                        }
                        ChargeListRow(
                            title = "安全温度上限",
                            value = "${current.safety_temp_max} °C",
                            onClick = {
                                edit = EditField("安全温度上限", "°C", true, 1, {
                                    current.safety_temp_max.toString()
                                }) {
                                    vm.updateCurrent { c ->
                                        c.copy(safety_temp_max = it.toIntOrNull() ?: c.safety_temp_max)
                                    }
                                }
                            },
                        )
                        ChargeChoiceRow(
                            title = "默认限流",
                            chips = ChargePresets.currentA,
                            selectedId = current.default_current_max_limit.toString(),
                            summary = String.format("%.1f A", current.default_current_max_limit / 1_000_000.0),
                            onSelect = {
                                vm.updateCurrent { c ->
                                    c.copy(
                                        default_current_max_limit = it.toLongOrNull()
                                            ?: c.default_current_max_limit,
                                    )
                                }
                            },
                            onCustom = {
                                edit = EditField("默认限流 (µA)", "µA", true, 100_000, {
                                    current.default_current_max_limit.toString()
                                }) {
                                    vm.updateCurrent { c ->
                                        c.copy(
                                            default_current_max_limit = it.toLongOrNull()
                                                ?: c.default_current_max_limit,
                                        )
                                    }
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
                                onClick = { vm.checkDaemon() },
                            )
                            ChargeSecondaryButton(
                                text = "下载并安装守护",
                                equalHeight = true,
                                onClick = {
                                    vm.installDaemon(v("native_impl").ifBlank { "rust" })
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
                    onClick = { vm.save(advancedOnly) },
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
