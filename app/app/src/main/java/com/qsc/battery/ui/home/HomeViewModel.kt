package com.qsc.battery.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.StatusBundle
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class HomeUiState(
    val status: StatusBundle = StatusBundle(),
    val conf: Map<String, String> = emptyMap(),
    val bootstrapped: Boolean = false,
    val rootSettled: Boolean = false,
)

/**
 * 首页状态：只读 Magisk 状态/软开关，不触碰 XP 充电节点。
 */
class HomeViewModel(
    private val container: AppContainer,
) : ViewModel() {
    private val _ui = MutableStateFlow(HomeUiState())
    val ui: StateFlow<HomeUiState> = _ui.asStateFlow()

    suspend fun refresh(full: Boolean = false) {
        val next = container.statusRepository.load()
        val conf = if (full || next.modulePresent) {
            if (next.modulePresent) container.configRepository.loadConf() else _ui.value.conf
        } else {
            _ui.value.conf
        }
        _ui.update {
            it.copy(
                status = next,
                conf = conf,
                rootSettled = true,
                bootstrapped = true,
            )
        }
    }

    fun setModuleEnabled(enabled: Boolean) {
        viewModelScope.launch {
            // Magisk soft switch only — APP never writes charge nodes
            container.statusRepository.setModuleEnabled(enabled)
            refresh(full = false)
        }
    }

    fun refreshAsync(full: Boolean = true) {
        viewModelScope.launch { refresh(full = full) }
    }
}
