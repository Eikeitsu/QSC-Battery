package com.qsc.battery.ui.log

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.ChargeEvent
import com.qsc.battery.data.model.LogLine
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class LogTab { Runtime, Events, Lsp }

data class LogUiState(
    val tab: LogTab = LogTab.Runtime,
    val level: String = "",
    val lines: List<LogLine> = emptyList(),
    val xpLines: List<LogLine> = emptyList(),
    val events: List<ChargeEvent> = emptyList(),
    val loading: Boolean = true,
)

/** 动态页：Magisk 运行/事件日志 + XP 稀疏日志（只读，不写充电节点）。 */
class LogViewModel(
    private val container: AppContainer,
) : ViewModel() {
    private val _ui = MutableStateFlow(LogUiState())
    val ui: StateFlow<LogUiState> = _ui.asStateFlow()

    fun setTab(tab: LogTab) {
        _ui.update { it.copy(tab = tab) }
        if (tab == LogTab.Lsp) refreshXp()
    }

    fun setLevel(level: String) {
        _ui.update { it.copy(level = level) }
    }

    fun refresh() {
        viewModelScope.launch {
            val cur = _ui.value
            _ui.update {
                it.copy(loading = cur.lines.isEmpty() && cur.events.isEmpty() && cur.xpLines.isEmpty())
            }
            val lines = container.logRepository.loadLogTail()
            val events = container.logRepository.loadEvents()
            val xp = if (cur.tab == LogTab.Lsp || cur.xpLines.isNotEmpty()) {
                container.logRepository.loadXpLog()
            } else {
                cur.xpLines
            }
            _ui.update {
                it.copy(lines = lines, events = events, xpLines = xp, loading = false)
            }
        }
    }

    fun refreshXp() {
        viewModelScope.launch {
            val xp = container.logRepository.loadXpLog()
            _ui.update { it.copy(xpLines = xp, loading = false) }
        }
    }

    fun clearCurrent() {
        viewModelScope.launch {
            when (_ui.value.tab) {
                LogTab.Runtime -> container.logRepository.clearLog()
                LogTab.Events -> container.logRepository.clearEvents()
                LogTab.Lsp -> container.logRepository.clearXpLog()
            }
            when (_ui.value.tab) {
                LogTab.Lsp -> refreshXp()
                else -> refresh()
            }
        }
    }
}
