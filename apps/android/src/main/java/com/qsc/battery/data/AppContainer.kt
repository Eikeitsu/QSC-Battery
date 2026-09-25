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
import com.qsc.battery.update.UpdateDownloadNotifier
import com.qsc.battery.update.UpdatesSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AppContainer(context: Context) {
    val appContext = context.applicationContext
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val root = RootBridge()
    val settingsRepository = SettingsRepository(appContext)
    val statusRepository = StatusRepository(root)
    val configRepository = ConfigRepository(root)
    val logRepository = LogRepository(appContext, root)
    val updateRepository = UpdateRepository(appContext, root)
    val moduleInstallRepository = ModuleInstallRepository(appContext, root, updateRepository)
    val daemonRepository = DaemonRepository(root)
    val profilesRepository = ProfilesRepository(root)
    val updateDownloadNotifier = UpdateDownloadNotifier(appContext)
    val updatesSession = UpdatesSession(
        updates = updateRepository,
        modules = moduleInstallRepository,
        daemon = daemonRepository,
        status = statusRepository,
        settings = settingsRepository,
        notifier = updateDownloadNotifier,
        scope = appScope,
    )

    /** XP 等入口请求打开动态页子 tab（runtime|events|lsp）；LogScreen 消费后清空。 */
    private val _pendingLogTab = MutableStateFlow<String?>(null)
    val pendingLogTab: StateFlow<String?> = _pendingLogTab.asStateFlow()

    fun requestLogTab(tab: String) {
        _pendingLogTab.value = tab
    }

    fun consumePendingLogTab(): String? {
        val tab = _pendingLogTab.value
        _pendingLogTab.value = null
        return tab
    }
}
