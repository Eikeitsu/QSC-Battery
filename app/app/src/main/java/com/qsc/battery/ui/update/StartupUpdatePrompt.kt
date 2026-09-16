package com.qsc.battery.ui.update

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * 冷启动后静默查一次正式版；有可升级项再弹窗。失败/已是最新不打扰。
 */
@Composable
fun StartupUpdatePrompt(
    container: AppContainer,
    onGoUpdates: () -> Unit,
) {
    var prompt by remember { mutableStateOf<UpdateCheckResult?>(null) }
    var dismissed by remember { mutableStateOf(false) }

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
        if (result.moduleHasUpdate || result.appHasUpdate || result.daemonHasUpdate) {
            prompt = result
        }
    }

    val r = prompt
    if (r == null || dismissed) return

    AlertDialog(
        onDismissRequest = { dismissed = true },
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
                    dismissed = true
                    prompt = null
                    container.updatesSession.setChannel(UpdateChannel.Stable)
                    onGoUpdates()
                },
            ) { Text("去更新") }
        },
        dismissButton = {
            TextButton(
                onClick = {
                    dismissed = true
                    prompt = null
                },
            ) { Text("稍后") }
        },
    )
}
