package com.qsc.battery.data.repo

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

class ModuleInstallRepository(
    private val context: Context,
    private val root: RootBridge,
    private val updates: UpdateRepository? = null,
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .build()
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun isHotUpdateBusy(): Boolean = root.exists(ModulePaths.HOT_UPDATE_LOCK)

    /** Install Magisk/KSU module zip via root. */
    suspend fun installModuleZip(zip: File): Result<String> = withContext(Dispatchers.IO) {
        if (!root.isRootAvailable()) return@withContext Result.failure(IllegalStateException("no root"))
        if (isHotUpdateBusy()) {
            return@withContext Result.failure(IllegalStateException("hot-update in progress"))
        }
        val path = zip.absolutePath.replace("'", "'\\''")
        val attempts = listOf(
            "magisk --install-module '$path'",
            "ksud module install '$path'",
            "nsenter --mount=/proc/1/ns/mnt -- /data/adb/ksud module install '$path'",
            "nsenter --mount=/proc/1/ns/mnt -- /data/adb/magisk/magisk --install-module '$path'",
        )
        var last = ""
        for (cmd in attempts) {
            val r = root.exec(cmd)
            last = (r.out + "\n" + r.err).trim()
            if (r.ok) return@withContext Result.success(last.ifBlank { "ok" })
        }
        Result.failure(IllegalStateException(last.ifBlank { "install failed" }))
    }

    /** Install companion APK via package installer UI (no silent install without priv). */
    fun promptInstallApk(apk: File) {
        val uri: Uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            apk,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    /** Download companion APK from app-update.json and install (root pm, else system installer). */
    suspend fun installCompanionApkOnline(): Result<String> = withContext(Dispatchers.IO) {
        val apkUrl = resolveApkUrl()
            ?: return@withContext Result.failure(IllegalStateException("无法解析 apkUrl"))
        val apk = if (updates != null) {
            updates.downloadToCache(apkUrl, "QSC-Battery-online.apk")
        } else {
            downloadApk(apkUrl)
        }
        if (root.isRootAvailable()) {
            val path = apk.absolutePath.replace("'", "'\\''")
            val r = root.exec("pm install -r '$path'")
            if (r.ok) return@withContext Result.success("installed")
        }
        withContext(Dispatchers.Main) { promptInstallApk(apk) }
        Result.success("installer-opened")
    }

    @Deprecated("Bundled APK removed; use installCompanionApkOnline")
    suspend fun installBundledApkFromModule(): Result<String> = installCompanionApkOnline()

    private fun resolveApkUrl(): String? {
        val req = Request.Builder().url(BuildConfig.APP_UPDATE_URL).get().build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return null
            val text = resp.body?.string().orEmpty()
            val obj = json.parseToJsonElement(text) as? JsonObject ?: return null
            return obj["apkUrl"]?.jsonPrimitive?.contentOrNull
        }
    }

    private fun downloadApk(url: String): File {
        val req = Request.Builder().url(url).get().build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("download failed: HTTP ${resp.code}")
            val body = resp.body ?: error("empty body")
            val out = File(context.cacheDir, "QSC-Battery-online.apk")
            out.outputStream().use { body.byteStream().copyTo(it) }
            return out
        }
    }
}
