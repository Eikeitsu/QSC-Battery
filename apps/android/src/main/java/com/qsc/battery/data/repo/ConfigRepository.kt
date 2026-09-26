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

    private fun confPathForKey(key: String): String = when {
        key in ConfigKeys.POWER -> ModulePaths.POWER_CONF
        key in ConfigKeys.NOTIFY -> ModulePaths.NOTIFY_CONF
        else -> ModulePaths.CONF
    }

    /** 通知 Magisk 服务：配置已变（与 conf mtime 双保险） */
    private suspend fun notifyConfReload() {
        root.exec("mkdir -p '${ModulePaths.DATADIR}'; : >'${ModulePaths.CONF_RELOAD_REQ}'")
    }

    suspend fun loadConf(): Map<String, String> {
        val map = ConfigKeys.DEFAULTS.toMutableMap()
        val files = listOf(ModulePaths.CONF, ModulePaths.POWER_CONF, ModulePaths.NOTIFY_CONF)
        for (file in files) {
            val text = root.readFile(file).orEmpty()
            text.lineSequence().forEach { line ->
                val t = line.trim()
                if (t.isEmpty() || t.startsWith("#")) return@forEach
                val i = t.indexOf('=')
                if (i <= 0) return@forEach
                val key = t.substring(0, i)
                if (key in ConfigKeys.ALL ||
                    key == "power_stop_schedule" ||
                    key == "notify_quiet_schedule" ||
                    key == "night_schedule" ||
                    key == "power_switch"
                ) {
                    map[key] = t.substring(i + 1)
                }
            }
        }
        return map.toMap()
    }

    suspend fun setConfValue(key: String, value: String): Boolean {
        val escaped = value.replace("'", "'\\''")
        val path = confPathForKey(key)
        val r = root.exec(
            "mkdir -p '${ModulePaths.MODDIR}/config'; " +
                "f='$path'; " +
                "touch \"\$f\"; " +
                "sed -i '/^$key=/d' \"\$f\"; " +
                "printf '%s=%s\\n' '$key' '$escaped' >> \"\$f\"",
        )
        if (r.ok) notifyConfReload()
        return r.ok
    }

    suspend fun setConfValues(values: Map<String, String>): Boolean {
        var ok = true
        values.forEach { (k, v) ->
            val escaped = v.replace("'", "'\\''")
            val path = confPathForKey(k)
            val r = root.exec(
                "mkdir -p '${ModulePaths.MODDIR}/config'; " +
                    "f='$path'; " +
                    "touch \"\$f\"; " +
                    "sed -i '/^$k=/d' \"\$f\"; " +
                    "printf '%s=%s\\n' '$k' '$escaped' >> \"\$f\"",
            )
            if (!r.ok) ok = false
        }
        if (ok) notifyConfReload()
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

    suspend fun loadSchedules(): Triple<List<String>, List<String>, List<String>> {
        val conf = root.readFile(ModulePaths.CONF).orEmpty()
        val notify = root.readFile(ModulePaths.NOTIFY_CONF).orEmpty()
        val power = root.readFile(ModulePaths.POWER_CONF).orEmpty()
        val stop = mutableListOf<String>()
        val quiet = mutableListOf<String>()
        val night = mutableListOf<String>()
        conf.lineSequence().forEach { line ->
            if (line.startsWith("power_stop_schedule=")) {
                stop += line.substringAfter("=").trim()
            }
        }
        notify.lineSequence().forEach { line ->
            if (line.startsWith("notify_quiet_schedule=")) {
                quiet += line.substringAfter("=").trim()
            }
        }
        power.lineSequence().forEach { line ->
            if (line.startsWith("night_schedule=")) {
                night += line.substringAfter("=").trim()
            }
        }
        return Triple(stop, quiet, night)
    }

    suspend fun replaceMultilineKey(key: String, lines: List<String>): Boolean {
        val path = when (key) {
            "notify_quiet_schedule" -> ModulePaths.NOTIFY_CONF
            "night_schedule" -> ModulePaths.POWER_CONF
            else -> ModulePaths.CONF
        }
        val r = root.exec(
            "mkdir -p '${ModulePaths.MODDIR}/config'; touch '$path'; sed -i '/^$key=/d' '$path'",
        )
        if (!r.ok) return false
        for (line in lines) {
            val escaped = line.replace("'", "'\\''")
            if (!root.exec("printf '%s=%s\\n' '$key' '$escaped' >> '$path'").ok) return false
        }
        notifyConfReload()
        return true
    }
}
