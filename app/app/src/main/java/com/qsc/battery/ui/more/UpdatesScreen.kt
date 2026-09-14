package com.qsc.battery.ui.more

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeChipTone
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeSegmented
import com.qsc.battery.ui.design.charge.ChargeStatusChip
import com.qsc.battery.ui.design.charge.ChargeTextAction
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTonalButton
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.update.UpdateTarget
import com.qsc.battery.update.UpdateWork
import com.qsc.battery.update.UpdatesSession

@Composable
fun UpdatesScreen(
    container: AppContainer,
    onBack: () -> Unit,
    snackbar: SnackbarHostState,
    onInstallModule: (zipUrl: String) -> Unit = {},
) {
    val session = container.updatesSession
    val channel by session.channel.collectAsState()
    val result by session.result.collectAsState()
    val work by session.work.collectAsState()
    val actionError by session.actionError.collectAsState()
    var showTech by remember { mutableStateOf(false) }
    var pendingCi by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val channelOptions = remember { UpdateChannel.entries.map { it.label } }
    val busy = work !is UpdateWork.Idle
    val checking = work is UpdateWork.Checking

    LaunchedEffect(Unit) {
        session.ensureBootstrapped()
        session.snackbar.collect { msg ->
            if (msg != null) {
                snackbar.showSnackbar(msg)
                session.consumeSnackbar()
            }
        }
    }

    if (pendingCi) {
        AlertDialog(
            onDismissRequest = { pendingCi = false },
            title = { Text("切换到 CI？") },
            text = {
                Text("开发构建可能不稳定，仅建议排查问题或尝鲜时使用。确认切换？")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingCi = false
                        session.setChannel(UpdateChannel.Ci)
                    },
                ) { Text("确认切换") }
            },
            dismissButton = {
                TextButton(onClick = { pendingCi = false }) { Text("取消") }
            },
        )
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(title = "更新", onBack = onBack)
        if (checking || work is UpdateWork.Downloading || work is UpdateWork.Installing) {
            val fraction = (work as? UpdateWork.Downloading)?.fraction
            if (fraction != null) {
                LinearProgressIndicator(
                    progress = { fraction },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(2.dp),
                    color = ChargeTheme.colors.accent,
                    trackColor = ChargeTheme.colors.stroke,
                )
            } else {
                LinearProgressIndicator(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(2.dp),
                    color = ChargeTheme.colors.accent,
                    trackColor = ChargeTheme.colors.stroke,
                )
            }
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
                .padding(
                    top = ChargeTheme.dimens.pageContentTop,
                    bottom = ChargeTheme.dimens.sectionGap,
                ),
            verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
        ) {
            Text(
                text = "检查模块、伴侣 APP 与充电守护是否有新版本。",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "更新通道",
                        style = ChargeTheme.typography.label,
                        color = ChargeTheme.colors.accent,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .weight(1f)
                            .padding(start = 4.dp),
                    )
                    Icon(
                        imageVector = Icons.Outlined.Refresh,
                        contentDescription = "刷新",
                        tint = if (busy) ChargeTheme.colors.muted else ChargeTheme.colors.accent,
                        modifier = Modifier
                            .size(36.dp)
                            .clickable(enabled = !busy) { session.refresh() }
                            .padding(6.dp),
                    )
                }
                ChargeSegmented(
                    options = channelOptions,
                    selectedIndex = channel.ordinal,
                    onSelect = { index ->
                        if (busy) return@ChargeSegmented
                        val next = UpdateChannel.entries.getOrElse(index) { UpdateChannel.Stable }
                        if (next == UpdateChannel.Ci && channel != UpdateChannel.Ci) {
                            pendingCi = true
                        } else {
                            session.setChannel(next)
                        }
                    },
                )
                Text(
                    text = when (channel) {
                        UpdateChannel.Stable -> "推荐大多数用户"
                        UpdateChannel.Prerelease -> "尝鲜功能，可能不稳定"
                        UpdateChannel.Ci -> "开发构建，风险较高"
                    },
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.muted,
                    modifier = Modifier.padding(start = 4.dp),
                )
                Row(
                    modifier = Modifier
                        .padding(start = 4.dp)
                        .clickable { showTech = !showTech },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Info,
                        contentDescription = null,
                        tint = ChargeTheme.colors.muted,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = if (showTech) "收起通道说明" else "了解通道",
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.muted,
                    )
                }
                if (showTech) {
                    Text(
                        text = when (channel) {
                            UpdateChannel.Stable ->
                                "正式：updates/stable；包地址通常指向 Pages。Magisk/KSU 模块列表仍只认 Pages update.json。"
                            UpdateChannel.Prerelease ->
                                "预发布：updates/prerelease，安装包多来自 GitHub Release。"
                            UpdateChannel.Ci ->
                                "CI：updates/ci → ci-dist 分支产物，随提交变化。"
                        },
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.muted,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
            }

            if (channel == UpdateChannel.Prerelease) {
                ChargeBanner(
                    text = "当前为预发布通道：功能可能不完整，建议重要设备优先使用正式版。",
                    tone = BannerTone.Info,
                )
            }

            val r = result
            if (r == null && checking) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = ChargeTheme.colors.accent,
                    )
                    Text(
                        text = "正在检查更新…",
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.muted,
                    )
                }
            }

            if (r != null) {
                val stableHint = buildString {
                    r.stableModuleNewer?.let {
                        append("正式模块 ${it.version}")
                    }
                    r.stableAppNewer?.let {
                        if (isNotEmpty()) append("；")
                        append("正式 APP ${it.version}")
                    }
                    r.stableDaemonNewer?.let {
                        if (isNotEmpty()) append("；")
                        append("正式守护 ${it.version}")
                    }
                }
                if (stableHint.isNotEmpty()) {
                    ChargeBanner(
                        text = "正式通道有新版本：$stableHint。",
                        tone = BannerTone.Info,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        ChargeTextAction(
                            text = "切换到正式",
                            enabled = !busy,
                            onClick = { session.setChannel(UpdateChannel.Stable) },
                        )
                    }
                }

                if (UpdatesSession.updatableCount(r) >= 2) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        ChargeTonalButton(
                            text = "全部更新",
                            enabled = !busy,
                            onClick = {
                                val moduleUrl = r.moduleRemote?.zipUrl
                                if (UpdatesSession.canUpdateModule(r) && !moduleUrl.isNullOrBlank()) {
                                    onInstallModule(moduleUrl)
                                } else {
                                    session.updateAll()
                                }
                            },
                        )
                    }
                }

                ProductCompactCard(
                    title = "模块",
                    localText = r.moduleLocal?.version ?: "未安装",
                    remoteText = r.moduleRemote?.version ?: "--",
                    chip = moduleChip(r),
                    changelog = r.moduleRemote?.changelog,
                    actionLabel = when {
                        r.moduleLocal == null && UpdatesSession.canUpdateModule(r) -> "安装"
                        UpdatesSession.canUpdateModule(r) -> "更新"
                        else -> null
                    },
                    work = work,
                    target = UpdateTarget.Module,
                    actionsEnabled = !busy,
                    onAction = {
                        val url = r.moduleRemote?.zipUrl ?: return@ProductCompactCard
                        onInstallModule(url)
                    },
                    onOpenChangelog = { url ->
                        runCatching {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url)),
                            )
                        }
                    },
                )

                ProductCompactCard(
                    title = "APP",
                    localText = r.appLocalVersion,
                    remoteText = r.appRemote?.version ?: "--",
                    chip = appChip(r),
                    changelog = r.appRemote?.changelog,
                    actionLabel = if (UpdatesSession.canUpdateApp(r)) "更新" else null,
                    work = work,
                    target = UpdateTarget.App,
                    actionsEnabled = !busy,
                    onAction = { session.updateTarget(UpdateTarget.App) },
                    onOpenChangelog = { url ->
                        runCatching {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url)),
                            )
                        }
                    },
                )

                ProductCompactCard(
                    title = "守护",
                    localText = r.daemonLocalVersion ?: "--",
                    remoteText = r.daemonRemote?.version ?: "--",
                    chip = daemonChip(r),
                    changelog = r.daemonRemote?.changelog,
                    actionLabel = if (UpdatesSession.canUpdateDaemon(r)) "更新" else null,
                    work = work,
                    target = UpdateTarget.Daemon,
                    actionsEnabled = !busy,
                    onAction = { session.updateTarget(UpdateTarget.Daemon) },
                    onOpenChangelog = { url ->
                        runCatching {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url)),
                            )
                        }
                    },
                )

                val err = actionError ?: r.error
                if (!err.isNullOrBlank()) {
                    ChargeBanner(text = err, tone = BannerTone.Warn)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        ChargeTextAction(
                            text = "重试",
                            enabled = !busy,
                            onClick = {
                                session.clearActionError()
                                session.refresh()
                            },
                        )
                    }
                }
            }
        }
    }
}

private data class ChipSpec(val text: String, val tone: ChargeChipTone)

private fun moduleChip(r: UpdateCheckResult): ChipSpec = when {
    r.moduleRemote == null -> ChipSpec("无数据", ChargeChipTone.Warn)
    r.moduleLocal == null -> ChipSpec("未安装", ChargeChipTone.Update)
    r.moduleHasUpdate -> ChipSpec("可更新", ChargeChipTone.Update)
    else -> ChipSpec("最新", ChargeChipTone.Ok)
}

private fun appChip(r: UpdateCheckResult): ChipSpec = when {
    r.appRemote == null -> ChipSpec("无数据", ChargeChipTone.Warn)
    r.appHasUpdate -> ChipSpec("可更新", ChargeChipTone.Update)
    else -> ChipSpec("最新", ChargeChipTone.Ok)
}

private fun daemonChip(r: UpdateCheckResult): ChipSpec = when {
    r.daemonRemote == null -> ChipSpec("无数据", ChargeChipTone.Warn)
    r.daemonHasUpdate -> ChipSpec("可更新", ChargeChipTone.Update)
    else -> ChipSpec("最新", ChargeChipTone.Ok)
}

@Composable
private fun ProductCompactCard(
    title: String,
    localText: String,
    remoteText: String,
    chip: ChipSpec,
    changelog: String?,
    actionLabel: String?,
    work: UpdateWork,
    target: UpdateTarget,
    actionsEnabled: Boolean,
    onAction: () -> Unit,
    onOpenChangelog: (String) -> Unit,
) {
    val active = when (work) {
        is UpdateWork.Downloading -> work.target == target
        is UpdateWork.Installing -> work.target == target
        else -> false
    }
    val progressLabel = when {
        work is UpdateWork.Downloading && work.target == target -> work.label
        work is UpdateWork.Installing && work.target == target -> work.label
        else -> null
    }
    val fraction = (work as? UpdateWork.Downloading)?.takeIf { it.target == target }?.fraction

    ChargeSection(title = title) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "$localText → $remoteText",
                    style = ChargeTheme.typography.body,
                    color = ChargeTheme.colors.ink,
                    fontWeight = FontWeight.Medium,
                )
                if (!changelog.isNullOrBlank()) {
                    Text(
                        text = "更新说明",
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.accent,
                        modifier = Modifier
                            .padding(top = 4.dp)
                            .clickable { onOpenChangelog(changelog) },
                    )
                }
            }
            ChargeStatusChip(text = chip.text, tone = chip.tone)
            if (!actionLabel.isNullOrBlank() && progressLabel == null) {
                ChargeTonalButton(
                    text = actionLabel,
                    enabled = actionsEnabled && !active,
                    onClick = onAction,
                )
            }
        }
        if (progressLabel != null) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = progressLabel,
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.accent,
                    fontWeight = FontWeight.Medium,
                )
                if (fraction != null) {
                    LinearProgressIndicator(
                        progress = { fraction },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(4.dp),
                        color = ChargeTheme.colors.accent,
                        trackColor = ChargeTheme.colors.stroke,
                    )
                } else {
                    LinearProgressIndicator(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(4.dp),
                        color = ChargeTheme.colors.accent,
                        trackColor = ChargeTheme.colors.stroke,
                    )
                }
            }
        }
    }
}
