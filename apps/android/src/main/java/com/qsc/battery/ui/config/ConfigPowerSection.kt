package com.qsc.battery.ui.config

import androidx.compose.runtime.Composable
import com.qsc.battery.ui.design.charge.ChargeChoiceRow
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePresets
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeToggleRow

@Composable
internal fun ConfigPowerSection(
    v: (String) -> String,
    setLocal: (String, String) -> Unit,
    onEdit: (ConfigEditField) -> Unit,
) {
    ChargeSection(title = "电量停充") {
        ChargeChoiceRow(
            title = "停止充电",
            chips = ChargePresets.powerStop,
            selectedId = v("power_stop").ifBlank { null },
            onSelect = {
                setLocal("power_stop", it)
                if (it != "100" && v("charge_full") == "1") {
                    setLocal("charge_full", "0")
                }
            },
            onCustom = {
                onEdit(
                    ConfigEditField("停止充电电量", "%", true, 1, { v("power_stop") }) {
                        setLocal("power_stop", it)
                        if (it != "100" && v("charge_full") == "1") {
                            setLocal("charge_full", "0")
                        }
                    },
                )
            },
        )
        ChargeDivider()
        ChargeChoiceRow(
            title = "恢复充电",
            chips = ChargePresets.powerStart,
            selectedId = v("power_start").ifBlank { null },
            onSelect = { setLocal("power_start", it) },
            onCustom = {
                onEdit(
                    ConfigEditField("恢复充电电量", "%", true, 1, { v("power_start") }) {
                        setLocal("power_start", it)
                    },
                )
            },
        )
        ChargeDivider()
        ChargeListRow(
            title = "延时停充",
            value = "${v("power_stop_time").ifBlank { "--" }} 秒",
            summary = if (v("charge_full") == "1" && v("power_stop") == "100") {
                "充满再停开启时延时不生效"
            } else {
                null
            },
            onClick = {
                onEdit(
                    ConfigEditField("延时停充", "秒", true, 1, { v("power_stop_time") }) {
                        setLocal("power_stop_time", it)
                    },
                )
            },
        )
        ChargeToggleRow(
            title = "充满再停",
            checked = v("charge_full") == "1" && v("power_stop") == "100",
            summary = if (v("power_stop") == "100") {
                "到 100% 后等涓流再停"
            } else {
                "需先把停止电量设为 100%"
            },
            enabled = v("power_stop") == "100",
            onCheckedChange = {
                if (it && v("power_stop") != "100") return@ChargeToggleRow
                setLocal("charge_full", if (it) "1" else "0")
            },
        )
        if (v("charge_full") == "1" && v("power_stop") == "100") {
            ChargeChoiceRow(
                title = "涓流模式",
                chips = ChargePresets.trickleMode,
                selectedId = v("charge_full_mode").ifBlank { "auto" },
                summary = when (v("charge_full_mode")) {
                    "time" -> "满电后再等约 10 分钟（时长仅配置文件可改）"
                    "current" -> "电流持续偏低后再停"
                    else -> "电流或时间任一满足即停"
                },
                onSelect = { setLocal("charge_full_mode", it) },
            )
        }
        ChargeToggleRow("自动拔插", v("power_reset") == "1") {
            setLocal("power_reset", if (it) "1" else "0")
        }
        ChargeToggleRow("兼容模式", v("compatibility_mode") == "1") {
            setLocal("compatibility_mode", if (it) "1" else "0")
        }
    }
}
