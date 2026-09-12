package com.qsc.battery.data.model

data class BatterySnapshot(
    val level: String = "",
    val temp: String = "",
    val status: String = "",
    val powered: Boolean = false,
    val source: String = "",
)

data class StatusBundle(
    val snapshot: BatterySnapshot = BatterySnapshot(),
    val moduleOff: Boolean = true,
    val chargingStopped: Boolean = false,
    val description: String = "",
    val voltage: String = "",
    val current: String = "",
    val version: String = "",
    val batteryInfo: String = "",
    val failed: Boolean = false,
    val modulePresent: Boolean = false,
    val rootOk: Boolean = false,
)

data class ModuleProp(
    val id: String = "",
    val name: String = "",
    val version: String = "",
    val versionCode: Long = 0,
    val description: String = "",
)

object ConfigKeys {
    val ALL = listOf(
        "power_stop", "power_start", "power_stop_time", "charge_full", "power_reset",
        "Compatibility_mode", "stop_hold_wakelock", "notify_charge_event", "notify_charge_kinds",
        "notify_power_status", "temperature_switch", "temperature_switch_stop",
        "temperature_switch_start", "loop_interval_sec", "loop_interval_maintain_sec",
        "switch_verify_sec", "wireless_policy", "app_stop", "app_stop_list",
        "history_enable", "history_interval_sec", "power_saver",
        "loop_interval_idle_sec", "loop_interval_idle_native_sec",
        "loop_interval_plugged_sec", "loop_interval_plugged_native_sec",
        "loop_interval_near_window", "native_daemon", "native_impl", "chart_show",
    )

    val DEFAULTS = mapOf(
        "power_stop" to "100",
        "power_start" to "95",
        "power_stop_time" to "3",
        "charge_full" to "0",
        "power_reset" to "0",
        "Compatibility_mode" to "0",
        "stop_hold_wakelock" to "auto",
        "notify_charge_event" to "0",
        "notify_charge_kinds" to "stop,resume,fail",
        "notify_power_status" to "0",
        "temperature_switch" to "1",
        "temperature_switch_stop" to "60",
        "temperature_switch_start" to "50",
        "loop_interval_sec" to "3",
        "loop_interval_maintain_sec" to "8",
        "switch_verify_sec" to "1",
        "wireless_policy" to "same",
        "app_stop" to "0",
        "app_stop_list" to "",
        "history_enable" to "1",
        "history_interval_sec" to "60",
        "power_saver" to "1",
        "loop_interval_idle_sec" to "90",
        "loop_interval_idle_native_sec" to "300",
        "loop_interval_plugged_sec" to "15",
        "loop_interval_plugged_native_sec" to "90",
        "loop_interval_near_window" to "3",
        "native_daemon" to "1",
        "native_impl" to "rust",
        "chart_show" to "1",
    )
}

@kotlinx.serialization.Serializable
data class CurrentConfig(
    val current_control: Int = 0,
    val bypass_enable: Int = 0,
    val battery_stop: Int = 110,
    val bypass_temp: Int = 110,
    val bypass_schedule: List<String> = emptyList(),
    val slow_charge: Int = 110,
    val default_current_max: Long = 5_000_000,
    val temperature_current: Int = 0,
    val default_current_limit: Int = 40,
    val default_current_max_limit: Long = 1_500_000,
    val temperature_current_limit: Int = 45,
    val constant_current_max: Long = 100_000,
    val app_limit: Int = 0,
    val app_current_max: Long = 200_000,
    val app_list: List<String> = listOf(
        "com.tencent.tmgp.sgame",
        "com.tencent.tmgp.pubgmhd",
        "com.miHoYo.Yuanshen",
        "com.tencent.lolm",
    ),
    val bypass_mode: String = "sim",
    val safety_temp_max: Int = 48,
    val battery_current: List<String> = listOf(
        "/sys/class/power_supply/battery/fast_charge_current",
        "/sys/class/power_supply/battery/current_max",
        "/sys/class/power_supply/battery/constant_charge_current",
        "/sys/class/power_supply/battery/constant_charge_current_max",
        "/sys/class/power_supply/main/constant_charge_current_max",
    ),
    val restricted: List<String> = listOf(
        "/sys/class/qcom-battery/restrict_chg value=1",
        "/sys/class/qcom-battery/restricted_charging value=1",
        "/sys/class/power_supply/battery/step_charging_enabled value=0",
    ),
    val current_reaffirm_sec: Int = 24,
    val current_drift_ua: Long = 300_000,
    val current_step_ua: Long = 0,
)

data class ChargeEvent(
    val ts: Long,
    val dateText: String,
    val timeText: String,
    val type: String,
    val level: Int?,
    val temp: Int?,
    val detail: String,
    val raw: String,
)

data class LogLine(
    val raw: String,
    val level: String,
)

data class RemoteUpdateInfo(
    val version: String,
    val versionCode: Long,
    val zipUrl: String? = null,
    val apkUrl: String? = null,
    val changelog: String? = null,
)

data class UpdateCheckResult(
    val moduleLocal: ModuleProp?,
    val moduleRemote: RemoteUpdateInfo?,
    val moduleHasUpdate: Boolean,
    val appLocalVersion: String,
    val appLocalCode: Long,
    val appRemote: RemoteUpdateInfo?,
    val appHasUpdate: Boolean,
    val error: String? = null,
)
