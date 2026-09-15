package com.qsc.battery.data.repo

import android.content.Context
import android.util.Log
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.GithubCdn
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

    private companion object {
        const val TAG = "QscUpdateCleanup"
    }

    data class ChannelDaemonPrep(
        val localManifest: String,
        val localBin: String?,
    )

    suspend fun check(
        statusRepo: StatusRepository,
        channel: UpdateChannel,
        preferCdn: Boolean = true,
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
        val moduleRemote = runCatching { resolveModule(channel, preferCdn) }
            .onFailure { err = it.message }
            .getOrNull()
        val appRemote = runCatching { resolveApp(channel, preferCdn) }
            .onFailure { if (err == null) err = it.message }
            .getOrNull()
        val daemonRemote = runCatching { resolveDaemon(channel, preferCdn) }
            .onFailure { if (err == null) err = it.message }
            .getOrNull()

        val daemonImpl = preferredDaemonImpl()
        val daemonLocalVersion = readDataFile(
            if (daemonImpl == "c") "native_version_c" else "native_version_rust",
        ) ?: readDataFile("native_version")
        val daemonLocalCode = (
            readDataFile(
                if (daemonImpl == "c") "native_version_code_c" else "native_version_code_rust",
            ) ?: readDataFile("native_version_code")
            )?.toLongOrNull() ?: 0L
        val daemonRemoteCode = daemonRemote?.versionCodeForImpl(daemonImpl) ?: 0L
        val daemonRemoteDisplay = daemonRemote?.let {
            it.copy(
                version = it.versionForImpl(daemonImpl),
                versionCode = daemonRemoteCode,
            )
        }

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
            val stableDaemonCode = stableDaemon?.versionCodeForImpl(daemonImpl) ?: 0L
            if (stableDaemon != null && stableDaemonCode > daemonLocalCode) {
                stableDaemonNewer = stableDaemon.copy(
                    version = stableDaemon.versionForImpl(daemonImpl),
                    versionCode = stableDaemonCode,
                )
            }
        }

        val moduleHasUpdate = moduleRemote != null &&
            localModule != null &&
            moduleRemote.versionCode > localModule.versionCode
        val moduleCanSwitch = moduleRemote != null &&
            !moduleRemote.zipUrl.isNullOrBlank() &&
            localModule != null &&
            moduleRemote.versionCode > 0L &&
            moduleRemote.versionCode < localModule.versionCode

        val appHasUpdate = appRemote != null && appRemote.versionCode > appCode
        val appCanSwitch = appRemote != null &&
            !appRemote.apkUrl.isNullOrBlank() &&
            appRemote.versionCode > 0L &&
            appRemote.versionCode < appCode

        val daemonHasUpdate = daemonRemoteDisplay != null &&
            daemonRemoteCode > 0L &&
            daemonRemoteCode > daemonLocalCode
        val daemonCanSwitch = daemonRemoteDisplay != null &&
            daemonRemoteDisplay.manifestUrl != null &&
            daemonRemoteCode > 0L &&
            daemonLocalCode > 0L &&
            daemonRemoteCode < daemonLocalCode

        UpdateCheckResult(
            channel = channel,
            moduleLocal = localModule,
            moduleRemote = moduleRemote,
            moduleHasUpdate = moduleHasUpdate,
            moduleCanSwitch = moduleCanSwitch,
            appLocalVersion = appName,
            appLocalCode = appCode,
            appRemote = appRemote,
            appHasUpdate = appHasUpdate,
            appCanSwitch = appCanSwitch,
            daemonLocalVersion = daemonLocalVersion,
            daemonLocalCode = daemonLocalCode,
            daemonRemote = daemonRemoteDisplay,
            daemonHasUpdate = daemonHasUpdate,
            daemonCanSwitch = daemonCanSwitch,
            daemonImpl = daemonImpl,
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
            // Site root（不含 /qscd）；fetch 会拼 /qscd/<name>。二进制优先走 manifest *Url（jsDelivr）
            UpdateChannel.Ci -> "https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@ci-dist"
            UpdateChannel.Prerelease -> "https://eikeitsu.github.io/QSC-Battery"
        }
        return manifest to pagesFallback
    }

    /**
     * APP OkHttp 拉清单 + 二进制，写入模块 data，供 qscd_fetch 走 QSCD_LOCAL_BIN
     *（避开设备 curl 访问 GitHub raw / 慢 CDN）。
     */
    suspend fun prepareChannelDaemonInstall(
        manifestUrl: String,
        impl: String,
        preferCdn: Boolean = true,
        onProgress: ((Long, Long?) -> Unit)? = null,
    ): ChannelDaemonPrep = withContext(Dispatchers.IO) {
        val reachable = metaUrl(manifestUrl, preferCdn)
        val req = Request.Builder()
            .url(reachable)
            .header("User-Agent", "QSC-Battery-App")
            .get()
            .build()
        val body = client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("daemon manifest HTTP ${resp.code}")
            resp.body.string()
        }
        val rewritten = GithubCdn.rewriteManifestBody(body, preferCdn)
        val localManifest = "${ModulePaths.DATADIR}/update_manifest.json"
        writeDataText(localManifest, rewritten)

        val arch = archSuffix()
        if (arch.isEmpty()) error("unsupported_arch")
        val binUrl = pickBinUrl(rewritten, impl, arch, preferCdn)
        if (binUrl.isBlank()) {
            return@withContext ChannelDaemonPrep(localManifest = localManifest, localBin = null)
        }
        val cache = downloadToCache(binUrl, "qscd_channel_bin", onProgress)
        val localBin = "${ModulePaths.DATADIR}/.qscd_channel_bin"
        val abs = cache.absolutePath.replace("'", "")
        val r = root.exec(
            "mkdir -p '${ModulePaths.DATADIR}' && " +
                "cp -f '$abs' '$localBin' && chmod 0755 '$localBin' && " +
                "[ -s '$localBin' ] && echo ok",
        )
        if (!r.ok || !r.out.contains("ok")) {
            error("write daemon binary failed: ${r.err.ifBlank { r.out }}")
        }
        runCatching {
            if (cache.isFile) {
                cache.delete()
                if (cache.isFile) {
                    Log.d(TAG, "cache still exists after delete: ${cache.absolutePath}")
                }
            }
        }
        ChannelDaemonPrep(localManifest = localManifest, localBin = localBin)
    }

    suspend fun cleanupChannelDaemonBin() {
        withContext(Dispatchers.IO) {
            val paths = listOf(
                "${ModulePaths.DATADIR}/.qscd_channel_bin",
                "${ModulePaths.DATADIR}/update_manifest.json",
            )
            for (path in paths) {
                silentUnlinkRootFile(path)
            }
        }
    }

    /** 静默删 APP 私有缓存更新包；不对用户提示，仅 debug 可查 */
    fun deleteCacheUpdateFile(fileName: String) {
        val name = fileName.trim().substringAfterLast('/').substringAfterLast('\\')
        if (name.isEmpty() || name == "." || name == "..") return
        val target = java.io.File(context.cacheDir, name)
        if (!target.isFile) return
        runCatching { target.delete() }
        if (target.isFile) {
            Log.d(TAG, "cache still exists after delete: ${target.absolutePath}")
        }
    }

    /** 仅删已知绝对路径普通文件；删不掉时打 debug */
    private suspend fun silentUnlinkRootFile(path: String) {
        val p = path.trim()
        if (!p.startsWith("/") || p.contains("..") || p.endsWith("/")) return
        val exists = root.exec("[ -f '$p' ] && echo yes || echo no")
        if (!exists.out.contains("yes")) return
        root.exec("rm -f -- '$p' >/dev/null 2>&1; true")
        val still = root.exec("[ -e '$p' ] && echo yes || echo no")
        if (still.out.contains("yes")) {
            Log.d(TAG, "still exists after unlink: $p")
        }
    }

    /**
     * APP 侧拉取清单并把 raw.githubusercontent.com 改成 jsDelivr，写入模块 data 目录，
     * 供 qscd_fetch 以本地文件读取（避开设备 curl 访问 GitHub raw）。
     */
    suspend fun materializeDaemonManifest(
        url: String,
        preferCdn: Boolean = true,
    ): String =
        withContext(Dispatchers.IO) {
            val reachable = metaUrl(url, preferCdn)
            val req = Request.Builder()
                .url(reachable)
                .header("User-Agent", "QSC-Battery-App")
                .get()
                .build()
            val body = client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) error("daemon manifest HTTP ${resp.code}")
                resp.body.string()
            }
            val rewritten = GithubCdn.rewriteManifestBody(body, preferCdn)
            val dest = "${ModulePaths.DATADIR}/update_manifest.json"
            writeDataText(dest, rewritten)
            dest
        }

    private suspend fun writeDataText(dest: String, text: String) {
        val b64 = android.util.Base64.encodeToString(
            text.toByteArray(Charsets.UTF_8),
            android.util.Base64.NO_WRAP,
        )
        val r = root.exec(
            "mkdir -p '${ModulePaths.DATADIR}' && " +
                "echo '$b64' | base64 -d > '$dest' && " +
                "chmod 0644 '$dest' && echo ok",
        )
        if (!r.ok || !r.out.contains("ok")) {
            error("write daemon manifest failed: ${r.err.ifBlank { r.out }}")
        }
    }

    private fun metaUrl(url: String, preferCdn: Boolean): String =
        GithubCdn.forCiMeta(GithubCdn.preferReachable(url), preferCdn)

    private fun archSuffix(): String {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
        return when {
            abi.startsWith("arm64") -> "arm64"
            abi.startsWith("armeabi") -> "arm"
            else -> ""
        }
    }

    private fun pickBinUrl(
        manifestText: String,
        impl: String,
        arch: String,
        preferCdn: Boolean,
    ): String {
        val name = "qscd-$impl-$arch"
        return try {
            val obj = json.parseToJsonElement(manifestText).jsonObject
            fun str(k: String) = obj[k]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
            val direct = str("${name}Url")
            if (direct.isNotEmpty()) {
                metaUrl(direct, preferCdn)
            } else {
                val base = str("baseUrl").trimEnd('/')
                if (base.isNotEmpty()) metaUrl("$base/$name", preferCdn) else ""
            }
        } catch (_: Exception) {
            ""
        }
    }

    private suspend fun preferredDaemonImpl(): String {
        val used = readDataFile("native_impl_used")?.lowercase()
        if (used == "rust" || used == "c") return used
        val conf = root.exec(
            "sed -n 's/^native_impl=//p' '${ModulePaths.CONF}' 2>/dev/null | head -1",
        ).out.trim().lowercase()
        return if (conf == "c") "c" else "rust"
    }

    private suspend fun readDataFile(name: String): String? {
        val r = root.exec("cat '${ModulePaths.DATADIR}/$name' 2>/dev/null")
        return r.out.trim().takeIf { r.ok && it.isNotEmpty() }
    }

    private fun resolveModule(channel: UpdateChannel, preferCdn: Boolean): RemoteUpdateInfo {
        val url = when (channel) {
            UpdateChannel.Stable -> BuildConfig.MODULE_UPDATE_URL
            UpdateChannel.Ci -> BuildConfig.CI_MODULE_UPDATE_URL
            UpdateChannel.Prerelease -> BuildConfig.PRE_MODULE_UPDATE_URL
        }
        return fetchUpdateJson(channelUrl(url, channel, preferCdn))
    }

    private fun resolveApp(channel: UpdateChannel, preferCdn: Boolean): RemoteUpdateInfo {
        val url = when (channel) {
            UpdateChannel.Stable -> BuildConfig.APP_UPDATE_URL
            UpdateChannel.Ci -> BuildConfig.CI_APP_UPDATE_URL
            UpdateChannel.Prerelease -> BuildConfig.PRE_APP_UPDATE_URL
        }
        return fetchUpdateJson(channelUrl(url, channel, preferCdn))
    }

    private fun resolveDaemon(channel: UpdateChannel, preferCdn: Boolean): RemoteUpdateInfo {
        val url = when (channel) {
            UpdateChannel.Stable -> BuildConfig.DAEMON_UPDATE_URL
            UpdateChannel.Ci -> BuildConfig.CI_DAEMON_UPDATE_URL
            UpdateChannel.Prerelease -> BuildConfig.PRE_DAEMON_UPDATE_URL
        }
        val fetchUrl = channelUrl(url, channel, preferCdn)
        return fetchDaemonJson(fetchUrl).copy(manifestUrl = fetchUrl)
    }

    private fun channelUrl(url: String, channel: UpdateChannel, preferCdn: Boolean): String =
        if (channel == UpdateChannel.Ci) metaUrl(url, preferCdn) else url

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
                rustVersion = str("rustVersion"),
                rustVersionCode = long("rustVersionCode"),
                cVersion = str("cVersion"),
                cVersionCode = long("cVersionCode"),
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
