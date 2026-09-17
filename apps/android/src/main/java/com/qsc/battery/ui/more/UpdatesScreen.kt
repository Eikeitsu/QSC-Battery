package com.qsc.battery.ui.more

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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.update.UpdateTarget
import com.qsc.battery.update.UpdateWork

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

    UpdateCiConfirmDialog(
        visible = pendingCi,
        onDismiss = { pendingCi = false },
        onConfirm = {
            pendingCi = false
            session.setChannel(UpdateChannel.Ci)
        },
    )

    UpdateSwitchConfirmDialog(
        target = pendingSwitch,
        result = result,
        onDismiss = { pendingSwitch = null },
        onConfirm = { switchTarget, r ->
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
    )

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
            UpdateChannelSection(
                channel = channel,
                channelOptions = channelOptions,
                preferCdn = preferCdn,
                busy = busy,
                showTech = showTech,
                onShowTechChange = { showTech = it },
                onPendingCi = { pendingCi = true },
                session = session,
            )

            if (channel == UpdateChannel.Prerelease) {
                UpdateInlineNotice(
                    text = "预发布通道：功能可能不完整，重要设备建议用正式版。",
                    tone = UpdateNoticeTone.Info,
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
                UpdateResultsSection(
                    r = r,
                    work = work,
                    busy = busy,
                    actionError = actionError,
                    actionErrorTarget = actionErrorTarget,
                    context = context,
                    session = session,
                    onInstallModule = onInstallModule,
                    onPendingSwitch = { pendingSwitch = it },
                )
            }
        }
    }
}
