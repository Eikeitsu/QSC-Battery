package com.qsc.battery.ui.more

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.ui.design.charge.ChargeChipTone
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeSegmented
import com.qsc.battery.ui.design.charge.ChargeStatusChip
import com.qsc.battery.ui.design.charge.ChargeTextAction
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
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
    val preferCdn by session.preferCdn.collectAsState()
    val result by session.result.collectAsState()
    val work by session.work.collectAsState()
    val actionError by session.actionError.collectAsState()
    val actionErrorTarget by session.actionErrorTarget.collectAsState()
    var showTech by remember { mutableStateOf(false) }
    var pendingCi by remember { mutableStateOf(false) }
    var pendingSwitch by remember { mutableStateOf<UpdateTarget?>(null) }
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

    val switchTarget = pendingSwitch
    if (switchTarget != null) {
        val r = result
        AlertDialog(
            onDismissRequest = { pendingSwitch = null },
            title = { Text("切回通道版本？") },
            text = {
                Text(
                    when (switchTarget) {
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
                TextButton(
                    onClick = {
                        pendingSwitch = null
                        when (switchTarget) {
                            UpdateTarget.Module -> {
                                val url = r?.moduleRemote?.zipUrl
                                if (!url.isNullOrBlank()) onInstallModule(url)
                            }
                            UpdateTarget.App, UpdateTarget.Daemon ->
                                session.updateTarget(switchTarget)
                        }
                    },
                ) { Text("确认切换") }
            },
            dismissButton = {
                TextButton(onClick = { pendingSwitch = null }) { Text("取消") }
            },
        )
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(
            title = "更新",
            onBack = onBack,
            subtitle = "检查并安装模块、伴侣 APP 与守护",
            actions = {
                Icon(
                    imageVector = Icons.Outlined.Refresh,
                    contentDescription = "刷新",
                    tint = if (busy) ChargeTheme.colors.muted else ChargeTheme.colors.accent,
                    modifier = Modifier
                        .size(40.dp)
                        .clickable(enabled = !busy) { session.refresh() }
                        .padding(8.dp),
                )
            },
        )
        // 仅「检查更新」用顶栏细条；下载/安装进度只在对应组件行内展示，避免双进度
        if (checking) {
            LinearProgressIndicator(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(2.dp),
                color = ChargeTheme.colors.accent,
                trackColor = ChargeTheme.colors.stroke,
            )
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
            ChargeSection(title = "更新通道") {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
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
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = when (channel) {
                                    UpdateChannel.Stable -> "推荐大多数用户"
                                    UpdateChannel.Prerelease -> "尝鲜功能，可能不稳定"
                                    UpdateChannel.Ci -> "开发构建，风险较高"
                                },
                                style = ChargeTheme.typography.caption,
                                color = ChargeTheme.colors.muted,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                text = if (showTech) "收起" else "了解通道",
                                style = ChargeTheme.typography.caption,
                                color = ChargeTheme.colors.accent,
                                fontWeight = FontWeight.Medium,
                                modifier = Modifier
                                    .clickable { showTech = !showTech }
                                    .padding(start = 8.dp, top = 2.dp, bottom = 2.dp),
                            )
                        }
                        if (showTech) {
                            Text(
                                text = when (channel) {
                                    UpdateChannel.Stable ->
                                        "正式：updates/stable；包地址通常指向 Pages。"
                                    UpdateChannel.Prerelease ->
                                        "预发布：updates/prerelease → GitHub Release。"
                                    UpdateChannel.Ci ->
                                        "CI：updates/ci → ci-dist（jsDelivr）产物。"
                                },
                                style = ChargeTheme.typography.caption,
                                color = ChargeTheme.colors.muted,
                            )
                        }
                    }
                    if (channel == UpdateChannel.Ci) {
                        ChargeDivider()
                        ChargeToggleRow(
                            title = "使用 CDN",
                            checked = preferCdn,
                            summary = "开启后 CI 走 jsDelivr（有缓存，刚发版检不到可关或稍后再试）；关闭则走 GitHub raw",
                            enabled = !busy,
                            onCheckedChange = { session.setPreferCdn(it) },
                        )
                    }
                }
            }

            if (channel == UpdateChannel.Prerelease) {
                InlineNotice(
                    text = "预发布通道：功能可能不完整，重要设备建议用正式版。",
                    tone = NoticeTone.Info,
                )
            }

            if (result == null && checking) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
                        .background(ChargeTheme.colors.surface)
                        .border(1.dp, ChargeTheme.colors.stroke, RoundedCornerShape(ChargeTheme.dimens.radiusMd))
                        .padding(horizontal = 16.dp, vertical = 18.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
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
                        modifier = Modifier.padding(start = 10.dp),
                    )
                }
            }

            val r = result
            if (r != null) {
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
                    InlineNotice(
                        text = "正式通道有新版本 · $stableHint",
                        tone = NoticeTone.Info,
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
                    InlineNotice(
                        text = "本地高于本通道（${switchHint.joinToString("、")}），可切回通道版；守护可热切换",
                        tone = NoticeTone.Info,
                    )
                }

                ChargeSection(title = "组件") {
                    ProductRow(
                        title = "模块",
                        localText = r.moduleLocal?.version ?: "未安装",
                        remoteText = r.moduleRemote?.version ?: "--",
                        chip = moduleChip(r),
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
                            val url = r.moduleRemote?.zipUrl ?: return@ProductRow
                            if (UpdatesSession.isModuleSwitch(r)) {
                                pendingSwitch = UpdateTarget.Module
                            } else {
                                onInstallModule(url)
                            }
                        },
                        onOpenChangelog = { openChangelog(context, it) },
                    )
                    ChargeDivider()
                    ProductRow(
                        title = "APP",
                        localText = r.appLocalVersion,
                        remoteText = r.appRemote?.version ?: "--",
                        chip = appChip(r),
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
                                pendingSwitch = UpdateTarget.App
                            } else {
                                session.updateTarget(UpdateTarget.App)
                            }
                        },
                        onOpenChangelog = { openChangelog(context, it) },
                    )
                    ChargeDivider()
                    ProductRow(
                        title = "守护 · ${if (r.daemonImpl == "c") "C" else "Rust"}",
                        localText = r.daemonLocalVersion ?: "--",
                        remoteText = r.daemonRemote?.version ?: "--",
                        chip = daemonChip(r),
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
                                pendingSwitch = UpdateTarget.Daemon
                            } else {
                                session.updateTarget(UpdateTarget.Daemon)
                            }
                        },
                        onOpenChangelog = { openChangelog(context, it) },
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
                                            pendingSwitch = UpdateTarget.Module
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
                    InlineNotice(
                        text = pageErr,
                        tone = NoticeTone.Warn,
                        action = "重试",
                        actionEnabled = !busy,
                        onAction = {
                            session.clearActionError()
                            session.refresh()
                        },
                    )
                }
            }
        }
    }
}

private fun openChangelog(context: android.content.Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }
}

private data class ChipSpec(val text: String, val tone: ChargeChipTone)

private fun moduleChip(r: UpdateCheckResult): ChipSpec = when {
    r.moduleRemote == null -> ChipSpec("无数据", ChargeChipTone.Warn)
    r.moduleLocal == null -> ChipSpec("未安装", ChargeChipTone.Update)
    r.moduleHasUpdate -> ChipSpec("可更新", ChargeChipTone.Update)
    r.moduleCanSwitch -> ChipSpec("可切换", ChargeChipTone.Update)
    else -> ChipSpec("最新", ChargeChipTone.Ok)
}

private fun appChip(r: UpdateCheckResult): ChipSpec = when {
    r.appRemote == null -> ChipSpec("无数据", ChargeChipTone.Warn)
    r.appHasUpdate -> ChipSpec("可更新", ChargeChipTone.Update)
    r.appCanSwitch -> ChipSpec("可切换", ChargeChipTone.Update)
    else -> ChipSpec("最新", ChargeChipTone.Ok)
}

private fun daemonChip(r: UpdateCheckResult): ChipSpec = when {
    r.daemonRemote == null -> ChipSpec("无数据", ChargeChipTone.Warn)
    r.daemonHasUpdate -> ChipSpec("可更新", ChargeChipTone.Update)
    r.daemonCanSwitch -> ChipSpec("可切换", ChargeChipTone.Update)
    else -> ChipSpec("最新", ChargeChipTone.Ok)
}

private fun versionLine(local: String, remote: String): String {
    val l = local.ifBlank { "--" }
    val r = remote.ifBlank { "--" }
    return if (l == r) l else "$l → $r"
}

private enum class NoticeTone { Info, Warn }

@Composable
private fun InlineNotice(
    text: String,
    tone: NoticeTone,
    action: String? = null,
    actionEnabled: Boolean = true,
    onAction: (() -> Unit)? = null,
) {
    val bg = when (tone) {
        NoticeTone.Info -> ChargeTheme.colors.accent.copy(alpha = 0.10f)
        NoticeTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.10f)
    }
    val border = when (tone) {
        NoticeTone.Info -> ChargeTheme.colors.accent.copy(alpha = 0.22f)
        NoticeTone.Warn -> ChargeTheme.colors.danger.copy(alpha = 0.24f)
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .background(bg)
            .border(1.dp, border, RoundedCornerShape(ChargeTheme.dimens.radiusMd))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = text,
            style = ChargeTheme.typography.caption,
            color = ChargeTheme.colors.ink,
            modifier = Modifier.weight(1f),
        )
        if (!action.isNullOrBlank() && onAction != null) {
            ChargeTextAction(
                text = action,
                enabled = actionEnabled,
                onClick = onAction,
            )
        }
    }
}

@Composable
private fun ProductRow(
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
    rowError: String? = null,
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

    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 12.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = title,
                style = ChargeTheme.typography.body,
                color = ChargeTheme.colors.ink,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            ChargeStatusChip(text = chip.text, tone = chip.tone)
            if (!actionLabel.isNullOrBlank() && progressLabel == null) {
                ChargeTonalButton(
                    text = actionLabel,
                    enabled = actionsEnabled && !active,
                    onClick = onAction,
                )
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = if (progressLabel == null && rowError.isNullOrBlank()) 12.dp else 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = versionLine(localText, remoteText),
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
                modifier = Modifier.weight(1f),
            )
            if (!changelog.isNullOrBlank()) {
                Text(
                    text = "说明",
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.accent,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.clickable { onOpenChangelog(changelog) },
                )
            }
        }
        if (progressLabel != null) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
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
                            .height(3.dp),
                        color = ChargeTheme.colors.accent,
                        trackColor = ChargeTheme.colors.stroke,
                    )
                } else {
                    LinearProgressIndicator(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(3.dp),
                        color = ChargeTheme.colors.accent,
                        trackColor = ChargeTheme.colors.stroke,
                    )
                }
            }
        }
        if (!rowError.isNullOrBlank()) {
            Text(
                text = rowError,
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.danger,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 12.dp),
            )
        }
    }
}
