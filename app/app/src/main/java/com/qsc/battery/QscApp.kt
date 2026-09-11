package com.qsc.battery

import android.app.Application
import com.qsc.battery.data.AppContainer
import com.topjohnwu.superuser.Shell

class QscApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        Shell.enableVerboseLogging = BuildConfig.DEBUG
        Shell.setDefaultBuilder(
            Shell.Builder.create()
                .setFlags(Shell.FLAG_MOUNT_MASTER)
                .setTimeout(15),
        )
        container = AppContainer(this)
    }
}
