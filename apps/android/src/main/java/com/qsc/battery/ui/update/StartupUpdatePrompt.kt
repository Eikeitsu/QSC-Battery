package com.qsc.battery.ui.update

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 冷启动后静默查一次正式版；有可升级项再弹窗。失败/已是最新不打扰。
 * 「稍后」会记住当前这批远端 versionCode，同一批不再弹；远端升号后才再提示。
 */
@Composable
fun StartupUpdatePrompt(
    container: AppContainer,
    onGoUpdates: () -> Unit,
) {
    var prompt by remember { mutableStateOf<UpdateCheckResult?>(null) }
    var dismissed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        delay(900)
        val result = withContext(Dispatchers.IO) {
            runCatching {
                container.updateRepository.check(
                    statusRepo = container.statusRepository,
                    channel = UpdateChannel.Stable,
                    preferCdn = false,
                )
            }.getOrNull()
        } ?: return@LaunchedEffect
        if (!(result.moduleHasUpdate || result.appHasUpdate || result.daemonHasUpdate)) {
            return@LaunchedEffect
        }
        val fp = startupUpdateFingerprint(result)
        val snoozed = withContext(Dispatchers.IO) {
            container.settingsRepository.startupUpdateSnooze()
        }
        if (fp.isNotEmpty() && fp == snoozed) return@LaunchedEffect
        prompt = result
    }

    val r = prompt
    if (r == null || dismissed) return

    fun snoozeAndClose() {
        dismissed = true
        prompt = null
        val fp = startupUpdateFingerprint(r)
        if (fp.isEmpty()) return
        scope.launch(Dispatchers.IO) {
            container.settingsRepository.setStartupUpdateSnooze(fp)
        }
    }

    AlertDialog(
        onDismissRequest = { snoozeAndClose() },
        title = { Text("发现正式版更新") },
        text = {
            Text(
                buildString {
                    append("当前通道检测仅限正式版：\n")
                    if (r.moduleHasUpdate) {
                        val local = r.moduleLocal?.version?.ifBlank { null } ?: "--"
                        val remote = r.moduleRemote?.version?.ifBlank { null } ?: "--"
                        append("· 模块 $local → $remote\n")
                    }
                    if (r.appHasUpdate) {
                        val remote = r.appRemote?.version?.ifBlank { null } ?: "--"
                        append("· APP ${r.appLocalVersion} → $remote\n")
                    }
                    if (r.daemonHasUpdate) {
                        val local = r.daemonLocalVersion?.ifBlank { null } ?: "--"
                        val remote = r.daemonRemote?.version?.ifBlank { null } ?: "--"
                        append("· 守护 $local → $remote\n")
                    }
                    append("\n可前往「我的 → 更新」安装。")
                }.trimEnd(),
            )
        },
        confirmButton = {
            TextButton(
                onClick = {
                    snoozeAndClose()
                    container.updatesSession.setChannel(UpdateChannel.Stable)
                    onGoUpdates()
                },
            ) { Text("去更新") }
        },
        dismissButton = {
            TextButton(onClick = { snoozeAndClose() }) { Text("稍后") }
        },
    )
}

private fun startupUpdateFingerprint(r: UpdateCheckResult): String = buildString {
    if (r.moduleHasUpdate) append("m").append(r.moduleRemote?.versionCode ?: 0)
    if (r.appHasUpdate) append("a").append(r.appRemote?.versionCode ?: 0)
    if (r.daemonHasUpdate) append("d").append(r.daemonRemote?.versionCode ?: 0)
}
