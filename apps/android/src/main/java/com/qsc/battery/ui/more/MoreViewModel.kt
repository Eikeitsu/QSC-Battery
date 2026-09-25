package com.qsc.battery.ui.more

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.PermStatus
import com.qsc.battery.core.PermissionChecker
import com.qsc.battery.data.AppContainer
import com.qsc.battery.xposed.XpRuntime
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class MoreUiState(
    val permHint: String = "",
    val xpStatus: XpRuntime.Status? = null,
    val debugOn: Boolean = false,
    val exporting: Boolean = false,
)

class MoreViewModel(
    private val container: AppContainer,
) : ViewModel() {
    private val checker = PermissionChecker(container.appContext)
    private val _ui = MutableStateFlow(MoreUiState())
    val ui: StateFlow<MoreUiState> = _ui.asStateFlow()

    fun refreshMeta() {
        viewModelScope.launch {
            val st = container.statusRepository.load()
            val snap = checker.snapshot(st.modulePresent, container.root)
            val xp = XpRuntime.probe(container.appContext, container.root)
            val debugOn = container.root.exists(ModulePaths.DEBUG_ON)
            val hint = buildString {
                append(if (snap.root == PermStatus.Ok) "Root ✓  " else "Root ✗  ")
                append(if (snap.modulePresent) "模块 ✓  " else "模块 ✗  ")
                append(if (snap.notifications == PermStatus.Ok) "通知 ✓  " else "通知 ✗  ")
                append(
                    when (xp.level) {
                        XpRuntime.Level.Active -> "XP ✓"
                        XpRuntime.Level.Enabled -> "XP 已启用"
                        XpRuntime.Level.Framework -> "XP 未启用"
                        XpRuntime.Level.ManagerOnly -> "XP 管理器 ○"
                        else -> "XP ✗"
                    },
                )
            }
            _ui.update { it.copy(permHint = hint, xpStatus = xp, debugOn = debugOn) }
        }
    }

    fun setDebugOn(enabled: Boolean) {
        viewModelScope.launch {
            val ok = if (enabled) {
                container.root.touch(ModulePaths.DEBUG_ON)
            } else {
                container.root.rm(ModulePaths.DEBUG_ON)
            }
            if (ok) {
                _ui.update { it.copy(debugOn = enabled) }
            }
        }
    }

    fun exportLogs(onResult: suspend (String) -> Unit) {
        if (_ui.value.exporting) return
        viewModelScope.launch {
            _ui.update { it.copy(exporting = true) }
            val result = container.logRepository.exportLogsZip()
            _ui.update { it.copy(exporting = false) }
            result.fold(
                onSuccess = { file ->
                    runCatching { container.logRepository.shareExportedLogs(file) }
                        .onSuccess { onResult("已打开分享：${file.name}") }
                        .onFailure { onResult("分享失败：${it.message ?: "未知错误"}") }
                },
                onFailure = { onResult("导出失败：${it.message ?: "未知错误"}") },
            )
        }
    }

    fun requestReOnboarding(onDone: suspend () -> Unit) {
        viewModelScope.launch {
            container.settingsRepository.setOnboardingDone(false)
            onDone()
        }
    }
}
