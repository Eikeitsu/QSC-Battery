package com.qsc.battery.update

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.qsc.battery.MainActivity

/**
 * 更新下载进度通知（无权限时静默跳过，页内进度仍可用）。
 */
class UpdateDownloadNotifier(private val context: Context) {
    private val nm = NotificationManagerCompat.from(context)
    private val appContext = context.applicationContext

    init {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "软件更新",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "模块 / APP / 守护下载与安装进度"
            }
            (appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    fun canNotify(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun start(title: String, text: String) {
        if (!canNotify()) return
        notifyProgress(title, text, indeterminate = true, progress = 0)
    }

    fun progress(title: String, text: String, fraction: Float?) {
        if (!canNotify()) return
        if (fraction == null) {
            notifyProgress(title, text, indeterminate = true, progress = 0)
        } else {
            notifyProgress(title, text, indeterminate = false, progress = (fraction * 100).toInt().coerceIn(0, 100))
        }
    }

    fun success(title: String, text: String) {
        if (!canNotify()) return
        val n = base(title, text)
            .setProgress(0, 0, false)
            .setOngoing(false)
            .setAutoCancel(true)
            .build()
        runCatching { nm.notify(NOTIFY_ID, n) }
    }

    fun failure(title: String, text: String) {
        if (!canNotify()) return
        val n = base(title, text)
            .setProgress(0, 0, false)
            .setOngoing(false)
            .setAutoCancel(true)
            .build()
        runCatching { nm.notify(NOTIFY_ID, n) }
    }

    fun cancel() {
        nm.cancel(NOTIFY_ID)
    }

    private fun notifyProgress(title: String, text: String, indeterminate: Boolean, progress: Int) {
        val builder = base(title, text).setOngoing(true)
        if (indeterminate) {
            builder.setProgress(0, 0, true)
        } else {
            builder.setProgress(100, progress, false)
        }
        runCatching { nm.notify(NOTIFY_ID, builder.build()) }
    }

    private fun base(title: String, text: String): NotificationCompat.Builder {
        val open = Intent(appContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            appContext,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pi)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
    }

    companion object {
        const val CHANNEL_ID = "qsc_updates"
        const val NOTIFY_ID = 42017
    }
}
