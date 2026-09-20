package com.qsc.battery.ui.more

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.qsc.battery.data.AppContainer
import com.qsc.battery.xposed.XpRuntime
import com.qsc.battery.xposed.XpServiceHolder
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class XpPanelUiState(
    val status: XpRuntime.Status? = null,
    val toggles: XpServiceHolder.ToggleState = XpServiceHolder.ToggleState(
        wakeEnabled = true,
        xpOff = false,
        verboseLog = false,
    ),
    val busy: Boolean = false,
    val message: String? = null,
)

/**
 * XP 面板：仅 LSPosed 作用域/开关与诊断。
 * 不停充、不写充电节点（Magisk 独占）。
 */
class XpPanelViewModel(
    private val container: AppContainer,
) : ViewModel() {
    private val _ui = MutableStateFlow(XpPanelUiState())
    val ui: StateFlow<XpPanelUiState> = _ui.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            val status = XpRuntime.probe(container.appContext, container.root)
            val toggles = XpServiceHolder.readToggleState(container.root)
            _ui.update { it.copy(status = status, toggles = toggles) }
        }
    }

    fun requestSystemScope() {
        viewModelScope.launch {
            _ui.update { it.copy(busy = true) }
            val msg = XpServiceHolder.requestSystemScope()
                ?: "LSPosed 服务未连接：请先在管理器启用本模块"
            refreshBlocking()
            _ui.update { it.copy(busy = false, message = msg) }
        }
    }

    fun setWakeEnabled(on: Boolean) {
        viewModelScope.launch {
            _ui.update { it.copy(busy = true) }
            XpServiceHolder.setWakeEnabled(on, container.root)
            refreshBlocking()
            _ui.update {
                it.copy(
                    busy = false,
                    message = if (on) "已允许边沿唤醒" else "已禁止边沿唤醒",
                )
            }
        }
    }

    fun setXpOff(on: Boolean) {
        viewModelScope.launch {
            _ui.update { it.copy(busy = true) }
            XpServiceHolder.setXpOff(on, container.root)
            refreshBlocking()
            _ui.update {
                it.copy(
                    busy = false,
                    message = if (on) "XP 已软关闭" else "XP 软关闭已解除",
                )
            }
        }
    }

    fun setVerboseLog(on: Boolean) {
        viewModelScope.launch {
            _ui.update { it.copy(busy = true) }
            XpServiceHolder.setVerboseLog(on, container.root)
            refreshBlocking()
            _ui.update { it.copy(busy = false) }
        }
    }

    fun setScreenEdge(on: Boolean) {
        viewModelScope.launch {
            _ui.update { it.copy(busy = true) }
            XpServiceHolder.setScreenEdge(on, container.root)
            refreshBlocking()
            _ui.update {
                it.copy(
                    busy = false,
                    message = if (on) "已开亮灭屏边沿" else "已关亮灭屏边沿",
                )
            }
        }
    }

    fun setDozeEdge(on: Boolean) {
        viewModelScope.launch {
            _ui.update { it.copy(busy = true) }
            XpServiceHolder.setDozeEdge(on, container.root)
            refreshBlocking()
            _ui.update {
                it.copy(
                    busy = false,
                    message = if (on) "已开 Doze 边沿" else "已关 Doze 边沿",
                )
            }
        }
    }

    fun setBcastEdge(on: Boolean) {
        viewModelScope.launch {
            _ui.update { it.copy(busy = true) }
            XpServiceHolder.setBcastEdge(on, container.root)
            refreshBlocking()
            _ui.update {
                it.copy(
                    busy = false,
                    message = if (on) "已开广播边沿" else "已关广播边沿",
                )
            }
        }
    }

    fun consumeMessage() {
        _ui.update { it.copy(message = null) }
    }

    private suspend fun refreshBlocking() {
        val status = XpRuntime.probe(container.appContext, container.root)
        val toggles = XpServiceHolder.readToggleState(container.root)
        _ui.update { it.copy(status = status, toggles = toggles) }
    }
}
