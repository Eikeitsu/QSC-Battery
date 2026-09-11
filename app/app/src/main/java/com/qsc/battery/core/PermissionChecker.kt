package com.qsc.battery.core

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.qsc.battery.xposed.XpRuntime
import com.topjohnwu.superuser.Shell
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class PermStatus { Ok, Missing, Unknown }

data class PermissionSnapshot(
    val root: PermStatus,
    val notifications: PermStatus,
    val installPackages: PermStatus,
    val xposedActive: PermStatus,
    val modulePresent: Boolean,
)

class PermissionChecker(private val context: Context) {
    suspend fun snapshot(modulePresent: Boolean): PermissionSnapshot = withContext(Dispatchers.IO) {
        val rootOk = runCatching { Shell.getShell().isRoot }.getOrDefault(false)
        PermissionSnapshot(
            root = if (rootOk) PermStatus.Ok else PermStatus.Missing,
            notifications = if (Build.VERSION.SDK_INT < 33) {
                PermStatus.Ok
            } else if (
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED
            ) {
                PermStatus.Ok
            } else {
                PermStatus.Missing
            },
            installPackages = if (context.packageManager.canRequestPackageInstalls()) {
                PermStatus.Ok
            } else {
                PermStatus.Missing
            },
            xposedActive = if (XpRuntime.isHooked) PermStatus.Ok else PermStatus.Missing,
            modulePresent = modulePresent,
        )
    }

    fun requestNotifications(activity: Activity) {
        if (Build.VERSION.SDK_INT >= 33) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_NOTIFY,
            )
        }
    }

    fun openInstallPermissionSettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    companion object {
        const val REQ_NOTIFY = 1001
    }
}
