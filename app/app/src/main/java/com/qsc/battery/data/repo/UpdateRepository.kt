package com.qsc.battery.data.repo

import android.content.Context
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import com.qsc.battery.data.model.RemoteUpdateInfo
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class UpdateRepository(
    private val context: Context,
    private val root: RootBridge,
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
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
        val daemonRemote = runCatching { resolveDaemon(channel) }
            .onFailure { if (err == null) err = it.message }
            .getOrNull()

        val daemonLocalVersion = readDataFile("native_version")
        val daemonLocalCode = readDataFile("native_version_code")?.toLongOrNull() ?: 0L

        var stableModuleNewer: RemoteUpdateInfo? = null
        var stableAppNewer: RemoteUpdateInfo? = null
        var stableDaemonNewer: RemoteUpdateInfo? = null
        if (channel != UpdateChannel.Stable) {
            val stableModule = runCatching { fetchUpdateJson(BuildConfig.MODULE_UPDATE_URL) }.getOrNull()
            val stableApp = runCatching { fetchUpdateJson(BuildConfig.APP_UPDATE_URL) }.getOrNull()
            val stableDaemon = runCatching { fetchDaemonJson(BuildConfig.DAEMON_UPDATE_URL) }.getOrNull()
            val localCode = localModule?.versionCode ?: 0L
            if (stableModule != null && stableModule.versionCode > localCode) {
                stableModuleNewer = stableModule
            }
            if (stableApp != null && stableApp.versionCode > appCode) {
                stableAppNewer = stableApp
            }
            if (stableDaemon != null && stableDaemon.versionCode > daemonLocalCode) {
                stableDaemonNewer = stableDaemon
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
            daemonLocalVersion = daemonLocalVersion,
            daemonLocalCode = daemonLocalCode,
            daemonRemote = daemonRemote,
            daemonHasUpdate = daemonRemote != null &&
                daemonRemote.versionCode > 0L &&
                daemonRemote.versionCode > daemonLocalCode,
            stableModuleNewer = stableModuleNewer,
            stableAppNewer = stableAppNewer,
            stableDaemonNewer = stableDaemonNewer,
            error = err,
        )
    }

    /**
     * @param onProgress (bytesRead, contentLengthOrNull) — 在 IO 线程回调，UI 侧自行切主线程。
     */
    suspend fun downloadToCache(
        url: String,
        fileName: String,
        onProgress: ((Long, Long?) -> Unit)? = null,
    ): java.io.File =
        withContext(Dispatchers.IO) {
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", "QSC-Battery-App")
                .get()
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) error("download failed: HTTP ${resp.code}")
                val body = resp.body
                val total = body.contentLength().takeIf { it >= 0L }
                val out = java.io.File(context.cacheDir, fileName)
                out.outputStream().use { sink ->
                    body.byteStream().use { src ->
                        val buf = ByteArray(DEFAULT_BUFFER_SIZE)
                        var readTotal = 0L
                        var lastEmit = -1L
                        while (true) {
                            val n = src.read(buf)
                            if (n < 0) break
                            sink.write(buf, 0, n)
                            readTotal += n
                            val pctStep = if (total != null && total > 0L) {
                                (readTotal * 100 / total) != lastEmit
                            } else {
                                readTotal - lastEmit >= 64 * 1024
                            }
                            if (onProgress != null && (pctStep || lastEmit < 0L)) {
                                lastEmit = if (total != null && total > 0L) readTotal * 100 / total else readTotal
                                onProgress(readTotal, total)
                            }
                        }
                        onProgress?.invoke(readTotal, total)
                    }
                }
                out
            }
        }

    fun channelDaemonUrls(channel: UpdateChannel): Pair<String, String> {
        val manifest = when (channel) {
            UpdateChannel.Stable -> BuildConfig.DAEMON_UPDATE_URL
            UpdateChannel.Ci -> BuildConfig.CI_DAEMON_UPDATE_URL
            UpdateChannel.Prerelease -> BuildConfig.PRE_DAEMON_UPDATE_URL
        }
        val pagesFallback = when (channel) {
            UpdateChannel.Stable -> "https://eikeitsu.github.io/QSC-Battery"
            UpdateChannel.Ci -> "https://raw.githubusercontent.com/Eikeitsu/QSC-Battery/ci-dist"
            UpdateChannel.Prerelease -> "https://eikeitsu.github.io/QSC-Battery"
        }
        return manifest to pagesFallback
    }

    private suspend fun readDataFile(name: String): String? {
        val r = root.exec("cat '${ModulePaths.DATADIR}/$name' 2>/dev/null")
        return r.out.trim().takeIf { r.ok && it.isNotEmpty() }
    }

    private fun resolveModule(channel: UpdateChannel): RemoteUpdateInfo = when (channel) {
        UpdateChannel.Stable -> fetchUpdateJson(BuildConfig.MODULE_UPDATE_URL)
        UpdateChannel.Ci -> fetchUpdateJson(BuildConfig.CI_MODULE_UPDATE_URL)
        UpdateChannel.Prerelease -> fetchUpdateJson(BuildConfig.PRE_MODULE_UPDATE_URL)
    }

    private fun resolveApp(channel: UpdateChannel): RemoteUpdateInfo = when (channel) {
        UpdateChannel.Stable -> fetchUpdateJson(BuildConfig.APP_UPDATE_URL)
        UpdateChannel.Ci -> fetchUpdateJson(BuildConfig.CI_APP_UPDATE_URL)
        UpdateChannel.Prerelease -> fetchUpdateJson(BuildConfig.PRE_APP_UPDATE_URL)
    }

    private fun resolveDaemon(channel: UpdateChannel): RemoteUpdateInfo {
        val url = when (channel) {
            UpdateChannel.Stable -> BuildConfig.DAEMON_UPDATE_URL
            UpdateChannel.Ci -> BuildConfig.CI_DAEMON_UPDATE_URL
            UpdateChannel.Prerelease -> BuildConfig.PRE_DAEMON_UPDATE_URL
        }
        return fetchDaemonJson(url).copy(manifestUrl = url)
    }

    private fun fetchUpdateJson(url: String): RemoteUpdateInfo {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "QSC-Battery-App")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return parseUpdateJson(resp.body.string())
        }
    }

    private fun fetchDaemonJson(url: String): RemoteUpdateInfo {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "QSC-Battery-App")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("daemon HTTP ${resp.code}")
            val obj = json.parseToJsonElement(resp.body.string()).jsonObject
            fun str(k: String) = obj[k]?.jsonPrimitive?.contentOrNull
            fun long(k: String) = obj[k]?.jsonPrimitive?.longOrNull ?: 0L
            return RemoteUpdateInfo(
                version = str("version").orEmpty(),
                versionCode = long("versionCode"),
                baseUrl = str("baseUrl"),
                changelog = str("changelog"),
                manifestUrl = url,
            )
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
}
