package com.qsc.battery.ui.config

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.design.charge.ChargeChip
import com.qsc.battery.ui.design.charge.ChargeChipGroup
import com.qsc.battery.ui.design.charge.ChargeChoiceRow
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePresets
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow

@Composable
internal fun ConfigAdvancedSections(
    vm: ConfigViewModel,
    ui: ConfigUiState,
    setLocal: (String, String) -> Unit,
    onEdit: (ConfigEditField) -> Unit,
    onEditNightSchedules: () -> Unit = {},
) {
    val conf = ui.conf
    fun v(key: String) = conf[key].orEmpty()
    val current = ui.current
    val stopSchedules = ui.stopSchedules
    val quietSchedules = ui.quietSchedules
    val nightSchedules = ui.nightSchedules
    val daemonStatus = ui.daemonStatus
    val notifyKinds = v("notify_charge_kinds")
        .split(',')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .toSet()
        .ifEmpty { setOf("stop", "resume", "fail") }

    ChargeSection(title = "省电策略") {
        ChargeToggleRow("省电模式", v("power_saver") != "0") {
            setLocal("power_saver", if (it) "1" else "0")
        }
        ChargeChoiceRow(
            title = "档位",
            chips = listOf(
                ChargeChip("balanced", "均衡"),
                ChargeChip("aggressive", "强力"),
                ChargeChip("custom", "自定义"),
            ),
            selectedId = v("power_profile").ifBlank { "balanced" },
            summary = "强力过夜更省；自定义可调秒数",
            onSelect = {
                when (it) {
                    "aggressive" -> {
                        vm.setLocals(
                            "power_profile" to it,
                            "loop_interval_idle_native_sec" to "3600",
                            "deep_idle_sec" to "7200",
                            "heartbeat_sec" to "1800",
                        )
                    }

                    "balanced" -> {
                        vm.setLocals(
                            "power_profile" to it,
                            "loop_interval_idle_native_sec" to "1800",
                            "deep_idle_sec" to "3600",
                            "heartbeat_sec" to "600",
                        )
                    }

                    else -> setLocal("power_profile", it)
                }
            },
        )
        ChargeDivider()
        ChargeToggleRow("息屏加强", v("screen_off_saver") != "0") {
            setLocal("screen_off_saver", if (it) "1" else "0")
        }
        ChargeToggleRow("夜间省电", v("night_saver") == "1") {
            setLocal("night_saver", if (it) "1" else "0")
            if (it) vm.ensureDefaultNightSchedule()
        }
        if (v("night_saver") == "1") {
            ChargeListRow(
                title = "夜间时段",
                summary = if (nightSchedules.isEmpty()) {
                    "未配置（点此添加，支持跨天）"
                } else {
                    nightSchedules.joinToString("；")
                },
                onClick = { onEditNightSchedules() },
            )
        }
        ChargeToggleRow("深睡", v("deep_idle_enable") != "0") {
            setLocal("deep_idle_enable", if (it) "1" else "0")
        }
        ChargeToggleRow(
            title = "动态简介",
            checked = v("description_enable") != "0",
            summary = "开：模块列表显示实时电量；关：固定文案更省。看区别→管理器模块列表本模块那一行",
            onCheckedChange = {
                setLocal("description_enable", if (it) "1" else "0")
            },
        )
        listOf(
            Triple("未插电间隔", "loop_interval_idle_sec", "秒"),
            Triple("未插电·有守护", "loop_interval_idle_native_sec", "秒"),
            Triple("插电远阈值", "loop_interval_plugged_sec", "秒"),
            Triple("插电·有守护", "loop_interval_plugged_native_sec", "秒"),
            Triple("近阈值间隔", "loop_interval_sec", "秒"),
            Triple("维持间隔", "loop_interval_maintain_sec", "秒"),
            Triple("近窗口", "loop_interval_near_window", "%"),
            Triple("深睡等待", "deep_after_sec", "秒"),
            Triple("深睡 idle", "deep_idle_sec", "秒(可达小时)"),
            Triple("心跳写盘节流", "heartbeat_sec", "秒"),
        ).forEach { (title, key, unit) ->
            ChargeListRow(
                title = title,
                value = "${v(key).ifBlank { "--" }} $unit",
                onClick = {
                    onEdit(ConfigEditField(title, unit, true, 1, { v(key) }) { setLocal(key, it) })
                },
            )
        }
        Text(
            text = "未插电由插拔事件唤醒；无守护时延迟约等于未插电/深睡 idle。非绝对零耗电。",
            style = ChargeTheme.typography.caption,
            color = ChargeTheme.colors.muted,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
    }

    ChargeSection(title = "停充行为") {
        ChargeChoiceRow(
            title = "停充后保持唤醒锁",
            chips = ChargePresets.wakeLock,
            selectedId = v("stop_hold_wakelock").ifBlank { "auto" },
            summary = "自动：仅息屏/夜间持锁，亮屏释放；强制开会持续挡 Doze",
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
            title = "拔线立刻还原节点",
            checked = v("unplug_restore") != "0",
            summary = "例：80%停充后拔线——开=立刻可再充；关=再插上仍停到恢复电量",
            onCheckedChange = {
                setLocal("unplug_restore", if (it) "1" else "0")
            },
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
        ChargeDivider()
        ChargeToggleRow(
            title = "事后电流硬复核",
            checked = v("switch_hard_verify") == "1",
            summary = "默认关（0814）；开=MCA 写后看电流，失败拉黑改试其它节点",
            onCheckedChange = {
                setLocal("switch_hard_verify", if (it) "1" else "0")
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
                onEdit(
                    ConfigEditField("App 停充列表", "", false, null, { v("app_stop_list") }) {
                        setLocal("app_stop_list", it)
                    },
                )
            },
        )
    }

    ChargeSection(title = "低电防护（冷门）") {
        Text(
            text = "默认全关。建议：提醒 15% / 关机 5% / 过温 55°C。低电仅未插电；过温插电也生效。",
            style = ChargeTheme.typography.caption,
            color = ChargeTheme.colors.muted,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        ChargeListRow(
            title = "填入建议值",
            summary = "15 / 5 / 55°C · 倒计时 60s · 开机满 900s",
            onClick = {
                setLocal("low_batt_warn", "15")
                setLocal("low_batt_shutdown", "5")
                setLocal("low_batt_temp_shutdown", "55")
                setLocal("low_batt_shutdown_delay_sec", "60")
                setLocal("low_batt_shutdown_min_uptime_sec", "900")
            },
        )
        ChargeListRow(
            title = "低电提醒 %",
            summary = v("low_batt_warn").ifBlank { "0" }.let {
                if (it == "0") "关" else "≤$it% 提醒"
            },
            onClick = {
                onEdit(
                    ConfigEditField("低电提醒", "% · 0=关，建议 15", true, 1, { v("low_batt_warn") }) {
                        setLocal("low_batt_warn", it)
                    },
                )
            },
        )
        ChargeListRow(
            title = "自动关机 %",
            summary = v("low_batt_shutdown").ifBlank { "0" }.let {
                if (it == "0") "关" else "≤$it% 关机"
            },
            onClick = {
                onEdit(
                    ConfigEditField("自动关机", "% · 0=关，建议 5", true, 1, {
                        v("low_batt_shutdown")
                    }) {
                        setLocal("low_batt_shutdown", it)
                    },
                )
            },
        )
        ChargeListRow(
            title = "过温关机 °C",
            summary = v("low_batt_temp_shutdown").ifBlank { "0" }.let {
                if (it == "0") "关" else "≥$it°C 关机"
            },
            onClick = {
                onEdit(
                    ConfigEditField("过温关机", "°C · 0=关，建议 55", true, 1, {
                        v("low_batt_temp_shutdown")
                    }) {
                        setLocal("low_batt_temp_shutdown", it)
                    },
                )
            },
        )
        ChargeListRow(
            title = "关机倒计时",
            summary = "${v("low_batt_shutdown_delay_sec").ifBlank { "60" }} 秒",
            onClick = {
                onEdit(
                    ConfigEditField("关机倒计时", "秒", true, 1, {
                        v("low_batt_shutdown_delay_sec")
                    }) {
                        setLocal("low_batt_shutdown_delay_sec", it)
                    },
                )
            },
        )
        ChargeListRow(
            title = "开机满秒才关",
            summary = v("low_batt_shutdown_min_uptime_sec").ifBlank { "900" }.let {
                if (it == "0") "不限制" else "${it}s"
            },
            onClick = {
                onEdit(
                    ConfigEditField("开机满秒才关", "秒 · 默认 900，0=不限", true, 1, {
                        v("low_batt_shutdown_min_uptime_sec")
                    }) {
                        setLocal("low_batt_shutdown_min_uptime_sec", it)
                    },
                )
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

    ChargeSection(title = "采样与曲线") {
        ChargeToggleRow("记录充放电历史", v("history_enable") == "1") {
            setLocal("history_enable", if (it) "1" else "0")
        }
        ChargeToggleRow("首页显示曲线（WebUI）", v("chart_show") == "1") {
            setLocal("chart_show", if (it) "1" else "0")
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
                onEdit(
                    ConfigEditField("安全温度上限", "°C", true, 1, {
                        current.safety_temp_max.toString()
                    }) {
                        vm.updateCurrent { c ->
                            c.copy(safety_temp_max = it.toIntOrNull() ?: c.safety_temp_max)
                        }
                    },
                )
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
                onEdit(
                    ConfigEditField("默认限流 (µA)", "µA", true, 100_000, {
                        current.default_current_max_limit.toString()
                    }) {
                        vm.updateCurrent { c ->
                            c.copy(
                                default_current_max_limit = it.toLongOrNull()
                                    ?: c.default_current_max_limit,
                            )
                        }
                    },
                )
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
