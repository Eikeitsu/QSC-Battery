package com.qsc.battery.ui.config

import androidx.compose.runtime.Composable
import com.qsc.battery.ui.design.charge.ChargeChoiceRow
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargePresets
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeToggleRow

@Composable
internal fun ConfigTempSection(
    conf: Map<String, String>,
    setLocal: (String, String) -> Unit,
    onEdit: (ConfigEditField) -> Unit,
) {
    fun v(key: String) = conf[key].orEmpty()
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
                onEdit(
                    ConfigEditField("停充温度", "°C", true, 1, { v("temperature_switch_stop") }) {
                        setLocal("temperature_switch_stop", it)
                    },
                )
            },
        )
        ChargeDivider()
        ChargeChoiceRow(
            title = "恢复温度",
            chips = ChargePresets.tempStart,
            selectedId = v("temperature_switch_start").ifBlank { null },
            onSelect = { setLocal("temperature_switch_start", it) },
            onCustom = {
                onEdit(
                    ConfigEditField("恢复温度", "°C", true, 1, { v("temperature_switch_start") }) {
                        setLocal("temperature_switch_start", it)
                    },
                )
            },
        )
    }
}
