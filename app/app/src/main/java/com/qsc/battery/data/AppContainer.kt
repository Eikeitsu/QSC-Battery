package com.qsc.battery.data

import android.content.Context
import com.qsc.battery.core.RootBridge
import com.qsc.battery.data.repo.ConfigRepository
import com.qsc.battery.data.repo.DaemonRepository
import com.qsc.battery.data.repo.LogRepository
import com.qsc.battery.data.repo.ModuleInstallRepository
import com.qsc.battery.data.repo.ProfilesRepository
import com.qsc.battery.data.repo.SettingsRepository
import com.qsc.battery.data.repo.StatusRepository
import com.qsc.battery.data.repo.UpdateRepository

class AppContainer(context: Context) {
    val appContext = context.applicationContext
    val root = RootBridge()
    val settingsRepository = SettingsRepository(appContext)
    val statusRepository = StatusRepository(root)
    val configRepository = ConfigRepository(root)
    val logRepository = LogRepository(root)
    val updateRepository = UpdateRepository(appContext)
    val moduleInstallRepository = ModuleInstallRepository(appContext, root)
    val daemonRepository = DaemonRepository(root)
    val profilesRepository = ProfilesRepository(root)
}
