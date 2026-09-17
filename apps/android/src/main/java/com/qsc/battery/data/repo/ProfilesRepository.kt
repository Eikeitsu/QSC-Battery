package com.qsc.battery.data.repo

import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.time.Instant

class ProfilesRepository(private val root: RootBridge) {
    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = true
    }

    suspend fun listNames(): List<String> {
        val text = root.readFile(ModulePaths.PROFILES) ?: return emptyList()
        return runCatching {
            val obj = json.parseToJsonElement(text).jsonObject
            obj.keys.sorted()
        }.getOrDefault(emptyList())
    }

    suspend fun saveProfile(name: String, conf: Map<String, String>, currentJson: String?): Boolean {
        val existingText = root.readFile(ModulePaths.PROFILES) ?: "{}"
        val existing = runCatching {
            json.parseToJsonElement(existingText).jsonObject.toMutableMap()
        }.getOrElse { mutableMapOf() }

        val confObj = buildJsonObject {
            conf.forEach { (k, v) -> put(k, v) }
        }
        existing[name] = buildJsonObject {
            put("savedAt", Instant.now().toString())
            put("conf", confObj)
            if (!currentJson.isNullOrBlank()) {
                put("current", json.parseToJsonElement(currentJson))
            }
        }
        val out = JsonObject(existing).toString()
        return root.writeFile(ModulePaths.PROFILES, out)
    }

    suspend fun applyProfile(name: String, configRepo: ConfigRepository): Boolean {
        val text = root.readFile(ModulePaths.PROFILES) ?: return false
        val obj = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return false
        val profile = obj[name]?.jsonObject ?: return false
        val conf = profile["conf"]?.jsonObject ?: return false
        val map = conf.mapValues { it.value.jsonPrimitive.contentOrNull.orEmpty() }
        if (!configRepo.setConfValues(map)) return false
        profile["current"]?.let { cur ->
            root.writeFile(ModulePaths.CURRENT, cur.toString())
        }
        return true
    }

    suspend fun exportBundle(): String? {
        val conf = root.readFile(ModulePaths.CONF).orEmpty()
        val current = root.readFile(ModulePaths.CURRENT).orEmpty()
        val profiles = root.readFile(ModulePaths.PROFILES).orEmpty()
        return buildJsonObject {
            put("conf", conf)
            put("current", current)
            put("profiles", profiles)
            put("exportedAt", Instant.now().toString())
        }.toString()
    }

    suspend fun importBundle(raw: String, configRepo: ConfigRepository): Boolean {
        val obj = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return false
        val confText = obj["conf"]?.jsonPrimitive?.contentOrNull
        val current = obj["current"]?.jsonPrimitive?.contentOrNull
        val profiles = obj["profiles"]?.jsonPrimitive?.contentOrNull
        if (!confText.isNullOrBlank()) {
            if (!root.writeFile(ModulePaths.CONF, confText)) return false
        }
        if (!current.isNullOrBlank()) {
            if (!root.writeFile(ModulePaths.CURRENT, current)) return false
        }
        if (!profiles.isNullOrBlank()) {
            if (!root.writeFile(ModulePaths.PROFILES, profiles)) return false
        }
        // touch conf so service notices; rewrite via set no-op if needed
        configRepo.setConfValue("_bundle_imported", System.currentTimeMillis().toString())
        configRepo.setConfValue("_bundle_imported", "")
        root.exec("sed -i '/^_bundle_imported=/d' '${ModulePaths.CONF}'")
        return true
    }
}
