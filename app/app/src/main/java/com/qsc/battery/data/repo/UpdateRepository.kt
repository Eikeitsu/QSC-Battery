package com.qsc.battery.data.repo

import android.content.Context
import com.qsc.battery.BuildConfig
import com.qsc.battery.data.model.RemoteUpdateInfo
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class UpdateRepository(private val context: Context) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun check(
        statusRepo: StatusRepository,
        channel: UpdateChannel,
    ): UpdateCheckResult = withContext(Dispatchers.IO) {
        val localModule = runCatching { statusRepo.readModuleProp() }.getOrNull()
        val appInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val appCode = if (android.os.Build.VERSION.SDK_INT >= 28) {
            appInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            appInfo.versionCode.toLong()
        }
        val appName = appInfo.versionName ?: BuildConfig.VERSION_NAME

        var err: String? = null
        val moduleRemote = runCatching { resolveModule(channel) }
            .onFailure { err = it.message }
            .getOrNull()
        val appRemote = runCatching { resolveApp(channel) }
            .onFailure { if (err == null) err = it.message }
            .getOrNull()

        var stableModuleNewer: RemoteUpdateInfo? = null
        var stableAppNewer: RemoteUpdateInfo? = null
        if (channel != UpdateChannel.Stable) {
            val stableModule = runCatching { fetchUpdateJson(BuildConfig.MODULE_UPDATE_URL) }.getOrNull()
            val stableApp = runCatching { fetchUpdateJson(BuildConfig.APP_UPDATE_URL) }.getOrNull()
            val localCode = localModule?.versionCode ?: 0L
            if (stableModule != null && stableModule.versionCode > localCode) {
                stableModuleNewer = stableModule
            }
            if (stableApp != null && stableApp.versionCode > appCode) {
                stableAppNewer = stableApp
            }
        }

        UpdateCheckResult(
            channel = channel,
            moduleLocal = localModule,
            moduleRemote = moduleRemote,
            moduleHasUpdate = moduleRemote != null &&
                localModule != null &&
                moduleRemote.versionCode > localModule.versionCode,
            appLocalVersion = appName,
            appLocalCode = appCode,
            appRemote = appRemote,
            appHasUpdate = appRemote != null && appRemote.versionCode > appCode,
            stableModuleNewer = stableModuleNewer,
            stableAppNewer = stableAppNewer,
            error = err,
        )
    }

    suspend fun downloadToCache(url: String, fileName: String): java.io.File =
        withContext(Dispatchers.IO) {
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", "QSC-Battery-App")
                .get()
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) error("download failed: HTTP ${resp.code}")
                val body = resp.body
                val out = java.io.File(context.cacheDir, fileName)
                out.outputStream().use { body.byteStream().copyTo(it) }
                out
            }
        }

    private fun resolveModule(channel: UpdateChannel): RemoteUpdateInfo = when (channel) {
        UpdateChannel.Stable -> fetchUpdateJson(BuildConfig.MODULE_UPDATE_URL)
        UpdateChannel.Ci -> fetchUpdateJson(BuildConfig.CI_MODULE_UPDATE_URL)
        UpdateChannel.Prerelease -> fetchPrerelease(preferZip = true)
    }

    private fun resolveApp(channel: UpdateChannel): RemoteUpdateInfo = when (channel) {
        UpdateChannel.Stable -> fetchUpdateJson(BuildConfig.APP_UPDATE_URL)
        UpdateChannel.Ci -> fetchUpdateJson(BuildConfig.CI_APP_UPDATE_URL)
        UpdateChannel.Prerelease -> fetchPrerelease(preferZip = false)
    }

    private fun fetchUpdateJson(url: String): RemoteUpdateInfo {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "QSC-Battery-App")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            val text = resp.body.string()
            return parseUpdateJson(text)
        }
    }

    private fun parseUpdateJson(text: String): RemoteUpdateInfo {
        val obj = json.parseToJsonElement(text).jsonObject
        fun str(k: String) = obj[k]?.jsonPrimitive?.contentOrNull
        fun long(k: String) = obj[k]?.jsonPrimitive?.longOrNull ?: 0L
        return RemoteUpdateInfo(
            version = str("version").orEmpty(),
            versionCode = long("versionCode"),
            zipUrl = str("zipUrl"),
            apkUrl = str("apkUrl"),
            changelog = str("changelog"),
        )
    }

    /** Newest non-draft prerelease that is not a CI tag. */
    private fun fetchPrerelease(preferZip: Boolean): RemoteUpdateInfo {
        val req = Request.Builder()
            .url(BuildConfig.GITHUB_RELEASES_URL)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "QSC-Battery-App")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("GitHub Releases HTTP ${resp.code}")
            val arr = json.parseToJsonElement(resp.body.string()) as JsonArray
            for (el in arr) {
                val obj = el.jsonObject
                val draft = obj["draft"]?.jsonPrimitive?.booleanOrNull == true
                val pre = obj["prerelease"]?.jsonPrimitive?.booleanOrNull == true
                if (draft || !pre) continue
                val tag = obj["tag_name"]?.jsonPrimitive?.contentOrNull.orEmpty()
                if (tag.startsWith("ci", ignoreCase = true) || tag.contains("ci-latest", true)) {
                    continue
                }
                val body = obj["body"]?.jsonPrimitive?.contentOrNull.orEmpty()
                val code = parseVersionCodeFromBody(body)
                    ?: error("prerelease $tag missing versionCode= in body")
                val assets = obj["assets"]?.jsonArray ?: JsonArray(emptyList())
                var zipUrl: String? = null
                var apkUrl: String? = null
                var version = tag.removePrefix("v").removePrefix("V")
                for (asset in assets) {
                    val a = asset.jsonObject
                    val name = a["name"]?.jsonPrimitive?.contentOrNull.orEmpty()
                    val url = a["browser_download_url"]?.jsonPrimitive?.contentOrNull
                    when {
                        name.endsWith("-full.zip") -> {
                            zipUrl = url
                            Regex("""QSC-Battery_v(.+)-full\.zip""").find(name)?.groupValues?.getOrNull(1)
                                ?.let { version = it }
                        }
                        name.endsWith(".apk") && name.startsWith("QSC-Battery") -> apkUrl = url
                    }
                }
                if (preferZip && zipUrl.isNullOrBlank()) continue
                if (!preferZip && apkUrl.isNullOrBlank()) {
                    // APP 通道：允许仅有 zip 的预发布（无 apk 时仍返回元数据）
                }
                return RemoteUpdateInfo(
                    version = version,
                    versionCode = code,
                    zipUrl = zipUrl,
                    apkUrl = apkUrl,
                    changelog = obj["html_url"]?.jsonPrimitive?.contentOrNull,
                )
            }
            error("暂无可用的预发布")
        }
    }

    private fun parseVersionCodeFromBody(body: String): Long? {
        Regex("""versionCode\s*[=:]\s*(\d+)""").find(body)?.groupValues?.getOrNull(1)
            ?.toLongOrNull()?.let { return it }
        Regex("""<!--\s*qsc:versionCode=(\d+)\s*-->""").find(body)?.groupValues?.getOrNull(1)
            ?.toLongOrNull()?.let { return it }
        return null
    }
}
