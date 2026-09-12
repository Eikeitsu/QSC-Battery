package com.qsc.battery

import android.app.Application
import com.qsc.battery.data.AppContainer
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
        Shell.enableVerboseLogging = BuildConfig.DEBUG
        Shell.setDefaultBuilder(
            Shell.Builder.create()
                .setFlags(Shell.FLAG_MOUNT_MASTER)
                .setTimeout(15),
        )
        container = AppContainer(this)
        appScope.launch {
            container.settingsRepository.syncLauncherIcon()
        }
    }
}
