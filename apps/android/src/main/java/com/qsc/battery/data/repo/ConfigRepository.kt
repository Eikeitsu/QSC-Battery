package com.qsc.battery.data.repo

import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import com.qsc.battery.data.model.ConfigKeys
import com.qsc.battery.data.model.CurrentConfig
import kotlinx.serialization.json.Json

class ConfigRepository(private val root: RootBridge) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    suspend fun loadConf(): Map<String, String> {
        val text = root.readFile(ModulePaths.CONF).orEmpty()
        val map = ConfigKeys.DEFAULTS.toMutableMap()
        text.lineSequence().forEach { line ->
            val t = line.trim()
            if (t.isEmpty() || t.startsWith("#")) return@forEach
            val i = t.indexOf('=')
            if (i <= 0) return@forEach
            val key = t.substring(0, i)
            if (key in ConfigKeys.ALL || key == "power_stop_schedule" || key == "notify_quiet_schedule" || key == "power_switch") {
                map[key] = t.substring(i + 1)
            }
        }
        return map
    }

    suspend fun setConfValue(key: String, value: String): Boolean {
        val escaped = value.replace("'", "'\\''")
        val r = root.exec(
            "f='${ModulePaths.CONF}'; " +
                "touch \"\$f\"; " +
                "sed -i '/^${key}=/d' \"\$f\"; " +
                "printf '%s=%s\\n' '$key' '$escaped' >> \"\$f\"",
        )
        return r.ok
    }

    suspend fun setConfValues(values: Map<String, String>): Boolean {
        var ok = true
        values.forEach { (k, v) -> if (!setConfValue(k, v)) ok = false }
        return ok
    }

    suspend fun loadCurrent(): CurrentConfig {
        val text = root.readFile(ModulePaths.CURRENT) ?: return CurrentConfig()
        return runCatching { json.decodeFromString<CurrentConfig>(text) }.getOrElse { CurrentConfig() }
    }

    suspend fun saveCurrent(cfg: CurrentConfig): Boolean {
        val text = json.encodeToString(CurrentConfig.serializer(), cfg)
        return root.writeFile(ModulePaths.CURRENT, text)
    }

    suspend fun loadSchedules(): Pair<List<String>, List<String>> {
        val text = root.readFile(ModulePaths.CONF).orEmpty()
        val stop = mutableListOf<String>()
        val quiet = mutableListOf<String>()
        text.lineSequence().forEach { line ->
            when {
                line.startsWith("power_stop_schedule=") ->
                    stop += line.substringAfter("=").trim()
                line.startsWith("notify_quiet_schedule=") ->
                    quiet += line.substringAfter("=").trim()
            }
        }
        return stop to quiet
    }

    suspend fun replaceMultilineKey(key: String, lines: List<String>): Boolean {
        val r = root.exec("sed -i '/^${key}=/d' '${ModulePaths.CONF}'")
        if (!r.ok) return false
        for (line in lines) {
            val escaped = line.replace("'", "'\\''")
            if (!root.exec("printf '%s=%s\\n' '$key' '$escaped' >> '${ModulePaths.CONF}'").ok) return false
        }
        return true
    }
}
