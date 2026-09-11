package com.qsc.battery.data.repo

import android.content.Context
import com.qsc.battery.BuildConfig
import com.qsc.battery.data.model.RemoteUpdateInfo
import com.qsc.battery.data.model.UpdateCheckResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class UpdateRepository(private val context: Context) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun check(
        statusRepo: StatusRepository,
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
        val moduleRemote = runCatching { fetchUpdate(BuildConfig.MODULE_UPDATE_URL) }
            .onFailure { err = it.message }
            .getOrNull()
        val appRemote = runCatching { fetchUpdate(BuildConfig.APP_UPDATE_URL) }
            .onFailure { if (err == null) err = it.message }
            .getOrNull()

        UpdateCheckResult(
            moduleLocal = localModule,
            moduleRemote = moduleRemote,
            moduleHasUpdate = moduleRemote != null &&
                localModule != null &&
                moduleRemote.versionCode > localModule.versionCode,
            appLocalVersion = appName,
            appLocalCode = appCode,
            appRemote = appRemote,
            appHasUpdate = appRemote != null && appRemote.versionCode > appCode,
            error = err,
        )
    }

    suspend fun downloadToCache(url: String, fileName: String): java.io.File = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url).get().build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("download failed: HTTP ${resp.code}")
            val body = resp.body ?: error("empty body")
            val out = java.io.File(context.cacheDir, fileName)
            out.outputStream().use { body.byteStream().copyTo(it) }
            out
        }
    }

    private fun fetchUpdate(url: String): RemoteUpdateInfo {
        val req = Request.Builder().url(url).get().build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            val text = resp.body?.string().orEmpty()
            val obj = json.parseToJsonElement(text) as JsonObject
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
}
