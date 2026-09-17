package com.qsc.battery.ui.more

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.update.UpdateTarget

@Composable
internal fun UpdateCiConfirmDialog(
    visible: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    if (!visible) return
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("切换到 CI？") },
        text = {
            Text("开发构建可能不稳定，仅建议排查问题或尝鲜时使用。确认切换？")
        },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text("确认切换") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
    )
}

@Composable
internal fun UpdateSwitchConfirmDialog(
    target: UpdateTarget?,
    result: UpdateCheckResult?,
    onDismiss: () -> Unit,
    onConfirm: (UpdateTarget, UpdateCheckResult?) -> Unit,
) {
    if (target == null) return
    val r = result
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("切回通道版本？") },
        text = {
            Text(
                when (target) {
                    UpdateTarget.Daemon ->
                        "本地守护高于当前通道，将热切换为通道版本（${r?.daemonRemote?.version ?: "--"}）。"
                    UpdateTarget.Module ->
                        "本地模块高于当前通道，将刷入通道包（${r?.moduleRemote?.version ?: "--"}），需在模块管理器中确认。"
                    UpdateTarget.App ->
                        "本地 APP 高于当前通道。系统通常拒绝降级安装，若失败请先卸载再装通道版（${r?.appRemote?.version ?: "--"}）。"
                },
            )
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(target, r) }) { Text("确认切换") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
    )
}
