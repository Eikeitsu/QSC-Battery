package com.qsc.battery.ui.config

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.CurrentConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ConfigUiState(
    val conf: Map<String, String> = emptyMap(),
    val current: CurrentConfig = CurrentConfig(),
    val ready: Boolean = false,
    val rootOk: Boolean = false,
    val moduleOk: Boolean = false,
    val daemonStatus: String = "",
    val stopSchedules: List<String> = emptyList(),
    val quietSchedules: List<String> = emptyList(),
    val nightSchedules: List<String> = emptyList(),
    val lastSaveMessage: String? = null,
    val lastDaemonMessage: String? = null,
)

/**
 * 策略页：读写 Magisk config/current；不经 XP 写充电节点。
 */
class ConfigViewModel(
    private val container: AppContainer,
) : ViewModel() {
    private val _ui = MutableStateFlow(ConfigUiState())
    val ui: StateFlow<ConfigUiState> = _ui.asStateFlow()

    fun v(key: String): String = _ui.value.conf[key].orEmpty()

    fun setLocal(key: String, value: String) {
        _ui.update { st ->
            st.copy(conf = st.conf.toMutableMap().apply { put(key, value) })
        }
    }

    fun updateCurrent(block: (CurrentConfig) -> CurrentConfig) {
        _ui.update { it.copy(current = block(it.current)) }
    }

    suspend fun reload() {
        val rootOk = container.root.isRootAvailable()
        val st = container.statusRepository.load()
        val moduleOk = st.modulePresent
        if (moduleOk) {
            val conf = container.configRepository.loadConf()
            val current = container.configRepository.loadCurrent()
            val daemonStatus = container.daemonRepository.status()
            val (stop, quiet, night) = container.configRepository.loadSchedules()
            _ui.update {
                it.copy(
                    rootOk = rootOk,
                    moduleOk = true,
                    conf = conf,
                    current = current,
                    daemonStatus = daemonStatus,
                    stopSchedules = stop,
                    quietSchedules = quiet,
                    nightSchedules = night,
                    ready = true,
                )
            }
        } else {
            _ui.update {
                it.copy(rootOk = rootOk, moduleOk = false, ready = true)
            }
        }
    }

    fun save(advancedOnly: Boolean) {
        viewModelScope.launch {
            val st = _ui.value
            val okConf = container.configRepository.setConfValues(st.conf)
            val okCur = container.configRepository.saveCurrent(st.current)
            val msg = if (okConf && okCur) {
                if (advancedOnly) "已保存" else "已保存，下一轮循环生效"
            } else {
                "保存失败"
            }
            _ui.update { it.copy(lastSaveMessage = msg) }
        }
    }

    fun consumeSaveMessage() {
        _ui.update { it.copy(lastSaveMessage = null) }
    }

    fun checkDaemon() {
        viewModelScope.launch {
            val msg = container.daemonRepository.check()
            val status = container.daemonRepository.status()
            _ui.update { it.copy(daemonStatus = status, lastDaemonMessage = msg) }
        }
    }

    fun installDaemon(impl: String) {
        viewModelScope.launch {
            val msg = container.daemonRepository.install(impl)
            val status = container.daemonRepository.status()
            _ui.update { it.copy(daemonStatus = status, lastDaemonMessage = msg) }
        }
    }

    fun consumeDaemonMessage() {
        _ui.update { it.copy(lastDaemonMessage = null) }
    }
}
