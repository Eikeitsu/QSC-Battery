package com.qsc.battery.ui.more

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTextAction
import com.qsc.battery.update.UpdateTarget
import com.qsc.battery.update.UpdateWork
import com.qsc.battery.update.UpdatesSession

@Composable
internal fun UpdateResultsSection(
    r: UpdateCheckResult,
    work: UpdateWork,
    busy: Boolean,
    actionError: String?,
    actionErrorTarget: UpdateTarget?,
    context: Context,
    session: UpdatesSession,
    onInstallModule: (zipUrl: String) -> Unit,
    onPendingSwitch: (UpdateTarget) -> Unit,
) {
    val stableHint = buildString {
        r.stableModuleNewer?.let { append("模块 ${it.version}") }
        r.stableAppNewer?.let {
            if (isNotEmpty()) append(" · ")
            append("APP ${it.version}")
        }
        r.stableDaemonNewer?.let {
            if (isNotEmpty()) append(" · ")
            append("守护 ${it.version}")
        }
    }
    if (stableHint.isNotEmpty()) {
        UpdateInlineNotice(
            text = "正式通道有新版本 · $stableHint",
            tone = UpdateNoticeTone.Info,
            action = "切换到正式",
            actionEnabled = !busy,
            onAction = { session.setChannel(UpdateChannel.Stable) },
        )
    }

    val switchHint = buildList {
        if (r.moduleCanSwitch) add("模块")
        if (r.appCanSwitch) add("APP")
        if (r.daemonCanSwitch) add("守护")
    }
    if (switchHint.isNotEmpty()) {
        UpdateInlineNotice(
            text = "本地高于本通道（${switchHint.joinToString("、")}），可切回通道版；守护可热切换",
            tone = UpdateNoticeTone.Info,
        )
    }

    ChargeSection(title = "组件") {
        UpdateProductRow(
            title = "模块",
            localText = r.moduleLocal?.version ?: "未安装",
            remoteText = r.moduleRemote?.version ?: "--",
            chip = updateModuleChip(r),
            changelog = r.moduleRemote?.changelog,
            actionLabel = when {
                r.moduleLocal == null && UpdatesSession.canUpdateModule(r) -> "安装"
                UpdatesSession.isModuleSwitch(r) -> "切换"
                UpdatesSession.canUpdateModule(r) -> "更新"
                else -> null
            },
            work = work,
            target = UpdateTarget.Module,
            actionsEnabled = !busy,
            onAction = {
                val url = r.moduleRemote?.zipUrl ?: return@UpdateProductRow
                if (UpdatesSession.isModuleSwitch(r)) {
                    onPendingSwitch(UpdateTarget.Module)
                } else {
                    onInstallModule(url)
                }
            },
            onOpenChangelog = { openUpdateChangelog(context, it) },
        )
        ChargeDivider()
        UpdateProductRow(
            title = "APP",
            localText = r.appLocalVersion,
            remoteText = r.appRemote?.version ?: "--",
            chip = updateAppChip(r),
            changelog = r.appRemote?.changelog,
            actionLabel = when {
                UpdatesSession.isAppSwitch(r) -> "切换"
                UpdatesSession.canUpdateApp(r) -> "更新"
                else -> null
            },
            work = work,
            target = UpdateTarget.App,
            actionsEnabled = !busy,
            onAction = {
                if (UpdatesSession.isAppSwitch(r)) {
                    onPendingSwitch(UpdateTarget.App)
                } else {
                    session.updateTarget(UpdateTarget.App)
                }
            },
            onOpenChangelog = { openUpdateChangelog(context, it) },
        )
        ChargeDivider()
        UpdateProductRow(
            title = "守护 · ${if (r.daemonImpl == "c") "C" else "Rust"}",
            localText = r.daemonLocalVersion ?: "--",
            remoteText = r.daemonRemote?.version ?: "--",
            chip = updateDaemonChip(r),
            changelog = r.daemonRemote?.changelog,
            actionLabel = when {
                UpdatesSession.isDaemonSwitch(r) -> "切换"
                UpdatesSession.canUpdateDaemon(r) -> "更新"
                else -> null
            },
            work = work,
            target = UpdateTarget.Daemon,
            actionsEnabled = !busy,
            onAction = {
                if (UpdatesSession.isDaemonSwitch(r)) {
                    onPendingSwitch(UpdateTarget.Daemon)
                } else {
                    session.updateTarget(UpdateTarget.Daemon)
                }
            },
            onOpenChangelog = { openUpdateChangelog(context, it) },
            rowError = actionError?.takeIf {
                actionErrorTarget == UpdateTarget.Daemon && it.isNotBlank()
            },
        )
        if (UpdatesSession.updatableCount(r) >= 2) {
            ChargeDivider()
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                ChargeTextAction(
                    text = if (
                        r.moduleCanSwitch || r.appCanSwitch || r.daemonCanSwitch
                    ) {
                        "全部处理"
                    } else {
                        "全部更新"
                    },
                    enabled = !busy,
                    onClick = {
                        val moduleUrl = r.moduleRemote?.zipUrl
                        if (UpdatesSession.canUpdateModule(r) && !moduleUrl.isNullOrBlank()) {
                            if (UpdatesSession.isModuleSwitch(r)) {
                                onPendingSwitch(UpdateTarget.Module)
                            } else {
                                onInstallModule(moduleUrl)
                            }
                        } else {
                            session.updateAll()
                        }
                    },
                )
            }
        }
    }

    val pageErr = when {
        !r.error.isNullOrBlank() -> r.error
        actionErrorTarget == null && !actionError.isNullOrBlank() -> actionError
        actionErrorTarget != null &&
            actionErrorTarget != UpdateTarget.Daemon &&
            !actionError.isNullOrBlank() -> actionError
        else -> null
    }
    if (!pageErr.isNullOrBlank()) {
        UpdateInlineNotice(
            text = pageErr,
            tone = UpdateNoticeTone.Warn,
            action = "重试",
            actionEnabled = !busy,
            onAction = {
                session.clearActionError()
                session.refresh()
            },
        )
    }
}
