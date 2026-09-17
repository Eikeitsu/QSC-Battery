package com.qsc.battery

import android.app.Application
import com.qsc.battery.data.AppContainer
import com.qsc.battery.icon.LauncherIconController
import com.qsc.battery.xposed.XpServiceHolder
import com.topjohnwu.superuser.Shell
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class QscApp : Application() {
    lateinit var container: AppContainer
        private set

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        // libxposed service：尽早注册 listener，经 XposedProvider 接收 LSPosed binder
        XpServiceHolder.install()
        Shell.enableVerboseLogging = BuildConfig.DEBUG
        Shell.setDefaultBuilder(
            Shell.Builder.create()
                .setFlags(Shell.FLAG_MOUNT_MASTER)
                .setTimeout(15),
        )
        container = AppContainer(this)
        appScope.launch {
            runCatching {
                container.settingsRepository.syncLauncherIcon(force = true)
            }.onFailure {
                LauncherIconController.restoreDefaultLauncher(this@QscApp)
            }
        }
    }
}
