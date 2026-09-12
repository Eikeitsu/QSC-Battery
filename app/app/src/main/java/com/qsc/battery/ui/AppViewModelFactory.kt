package com.qsc.battery.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.config.ConfigViewModel
import com.qsc.battery.ui.home.HomeViewModel
import com.qsc.battery.ui.log.LogViewModel
import com.qsc.battery.ui.more.MoreViewModel
import com.qsc.battery.ui.more.XpPanelViewModel

class AppViewModelFactory(
    private val container: AppContainer,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        val vm = when {
            modelClass.isAssignableFrom(HomeViewModel::class.java) -> HomeViewModel(container)
            modelClass.isAssignableFrom(ConfigViewModel::class.java) -> ConfigViewModel(container)
            modelClass.isAssignableFrom(LogViewModel::class.java) -> LogViewModel(container)
            modelClass.isAssignableFrom(MoreViewModel::class.java) -> MoreViewModel(container)
            modelClass.isAssignableFrom(XpPanelViewModel::class.java) -> XpPanelViewModel(container)
            else -> throw IllegalArgumentException("Unknown ViewModel: ${modelClass.name}")
        }
        return vm as T
    }
}
