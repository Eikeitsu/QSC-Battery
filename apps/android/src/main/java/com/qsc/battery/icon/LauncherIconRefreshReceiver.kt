package com.qsc.battery.icon

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.qsc.battery.QscApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * 插拔电 / 低电量阈值等稀疏广播时刷新桌面图标档位。
 * 故意不监听 ACTION_BATTERY_CHANGED。
 */
class LauncherIconRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        when (action) {
            Intent.ACTION_POWER_CONNECTED,
            Intent.ACTION_POWER_DISCONNECTED,
            Intent.ACTION_BATTERY_LOW,
            Intent.ACTION_BATTERY_OKAY,
            -> Unit
            else -> return
        }
        val app = context.applicationContext
        val pending = goAsync()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        scope.launch {
            try {
                val container = (app as? QscApp)?.container
                if (container != null) {
                    LauncherIconController.syncFromSettings(app, container.settingsRepository)
                } else {
                    // 进程未就绪时与默认偏好一致：动态关、非备用
                    LauncherIconController.apply(app, alternative = false, dynamic = false)
                }
            } finally {
                pending.finish()
            }
        }
    }
}
