package com.qsc.battery.data.repo

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class ModuleInstallRepository(
    private val context: Context,
    private val root: RootBridge,
) {
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

    /** Assets APK shipped inside module tree. */
    suspend fun installBundledApkFromModule(): Result<String> = withContext(Dispatchers.IO) {
        val candidates = listOf(
            "${ModulePaths.MODDIR}/app/QSC-Battery.apk",
            "${ModulePaths.MODDIR}/app/qsc-battery.apk",
        )
        val apk = candidates.firstOrNull { root.exists(it) }
            ?: return@withContext Result.failure(IllegalStateException("bundled apk missing"))
        val r = root.exec("pm install -r '$apk'")
        if (r.ok) Result.success("installed")
        else Result.failure(IllegalStateException((r.out + r.err).trim()))
    }
}
