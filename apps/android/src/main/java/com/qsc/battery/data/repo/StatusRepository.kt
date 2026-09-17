package com.qsc.battery.data.repo

import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import com.qsc.battery.data.model.BatterySnapshot
import com.qsc.battery.data.model.ModuleProp
import com.qsc.battery.data.model.StatusBundle

class StatusRepository(private val root: RootBridge) {
    suspend fun load(): StatusBundle {
        val rootOk = root.isRootAvailable()
        if (!rootOk) {
            return StatusBundle(rootOk = false, modulePresent = false, moduleOff = true)
        }
        val present = root.exists(ModulePaths.MODULE_PROP)
        if (!present) {
            return StatusBundle(rootOk = true, modulePresent = false, moduleOff = true)
        }

        val helper = ModulePaths.STATUS_HELPER
        val cmd = if (root.exists(helper)) {
            "sh '$helper'"
        } else {
            inlineStatusCmd()
        }
        val result = root.exec(cmd)
        if (!result.ok) {
            return StatusBundle(rootOk = true, modulePresent = true, moduleOff = true)
        }
        return parseBundle(result.out).copy(rootOk = true, modulePresent = true)
    }

    suspend fun readModuleProp(): ModuleProp? {
        val text = root.readFile(ModulePaths.MODULE_PROP) ?: return null
        fun grab(key: String) = text.lineSequence().firstOrNull { it.startsWith("$key=") }?.substringAfter("=")?.trim().orEmpty()
        return ModuleProp(
            id = grab("id"),
            name = grab("name"),
            version = grab("version"),
            versionCode = grab("versionCode").toLongOrNull() ?: 0L,
            description = grab("description"),
        )
    }

    suspend fun setModuleEnabled(enabled: Boolean): Boolean = if (enabled) root.rm(ModulePaths.MODULE_OFF_FLAG) else root.touch(ModulePaths.MODULE_OFF_FLAG)

    private fun inlineStatusCmd(): String = buildString {
        append("MODDIR='${ModulePaths.MODDIR}'; ")
        append(". '${ModulePaths.COMMON_SH}' 2>/dev/null || true; ")
        append("printf '__QSC_SNAPSHOT__\\n'; ")
        append("if command -v qsc_battery_snapshot_print >/dev/null 2>&1; then qsc_battery_snapshot_print; ")
        append("else ")
        append("echo level=\$(cat /sys/class/power_supply/battery/capacity 2>/dev/null); ")
        append("echo temp=\$(cat /sys/class/power_supply/battery/temp 2>/dev/null); ")
        append("echo status=\$(cat /sys/class/power_supply/battery/status 2>/dev/null); ")
        append("echo plugged=\$(cat /sys/class/power_supply/battery/online 2>/dev/null); ")
        append("fi; ")
        append("printf '__QSC_MODULE_OFF__\\n'; ")
        append("[ -f '${ModulePaths.MODULE_OFF_FLAG}' ] || [ -f '${ModulePaths.MODDIR}/disable' ] && echo 1 || echo 0; ")
        append("printf '__QSC_CHARGING_STOPPED__\\n'; ")
        append("[ -f '${ModulePaths.POWER_SWITCH_FLAG}' ] && echo 1 || echo 0; ")
        append("printf '__QSC_DESCRIPTION__\\n'; ")
        append("grep '^description=' '${ModulePaths.MODULE_PROP}' 2>/dev/null | cut -d= -f2-; ")
        append("printf '__QSC_VOLTAGE__\\n'; cat /sys/class/power_supply/battery/voltage_now 2>/dev/null; ")
        append("printf '__QSC_CURRENT__\\n'; cat /sys/class/power_supply/battery/current_now 2>/dev/null; ")
        append("printf '__QSC_VERSION__\\n'; ")
        append("grep '^version=' '${ModulePaths.MODULE_PROP}' 2>/dev/null | cut -d= -f2-; ")
        append("printf '__QSC_BATTERY__\\n'; sh '${ModulePaths.BATTERY_INFO}' 2>/dev/null; ")
        append("printf '__QSC_FAILED__\\n'; ")
        append("[ -f '${ModulePaths.DATADIR}/stop_fail_hint' ] || [ -f '${ModulePaths.DATADIR}/no_node_logged' ] && echo 1 || echo 0")
    }

    private fun section(text: String, name: String): String {
        val marker = "__QSC_${name}__"
        val start = text.indexOf(marker)
        if (start < 0) return ""
        val bodyStart = text.indexOf('\n', start)
        if (bodyStart < 0) return ""
        val next = text.indexOf("\n__QSC_", bodyStart + 1)
        return text.substring(bodyStart + 1, if (next < 0) text.length else next).trim()
    }

    private fun parseSnapshot(raw: String): BatterySnapshot {
        fun kv(key: String): String {
            val line = raw.lineSequence().firstOrNull { it.startsWith("$key=") } ?: return ""
            return line.substringAfter("=").trim()
        }
        val plugged = kv("plugged").ifEmpty { kv("powered") }
        return BatterySnapshot(
            level = kv("level"),
            temp = kv("temp"),
            status = kv("status"),
            powered = plugged == "1" || plugged.equals("true", true),
            source = kv("source"),
        )
    }

    private fun parseBundle(stdout: String): StatusBundle {
        val snapRaw = section(stdout, "SNAPSHOT")
        return StatusBundle(
            snapshot = parseSnapshot(snapRaw),
            moduleOff = section(stdout, "MODULE_OFF") == "1",
            chargingStopped = section(stdout, "CHARGING_STOPPED") == "1",
            description = section(stdout, "DESCRIPTION"),
            voltage = section(stdout, "VOLTAGE"),
            current = section(stdout, "CURRENT"),
            version = section(stdout, "VERSION"),
            batteryInfo = section(stdout, "BATTERY"),
            failed = section(stdout, "FAILED") == "1",
        )
    }
}
