package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeSegmented
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTopBar
import kotlinx.coroutines.launch

@Composable
fun UpdatesScreen(
    container: AppContainer,
    onBack: () -> Unit,
    snackbar: SnackbarHostState,
) {
    var channel by remember { mutableStateOf(UpdateChannel.Stable) }
    var result by remember { mutableStateOf<UpdateCheckResult?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val channelOptions = remember { UpdateChannel.entries.map { it.label } }

    LaunchedEffect(Unit) {
        channel = container.settingsRepository.updateChannel()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(title = "更新", onBack = onBack)
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
                text = "选择更新通道后检查模块与伴侣 APP。正式版走文档站；预发布直连 GitHub Release；CI 走 ci-dist 滚动构建。",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )

            ChargeSection(title = "更新通道") {
                ChargeSegmented(
                    options = channelOptions,
                    selectedIndex = channel.ordinal,
                    onSelect = { index ->
                        val next = UpdateChannel.entries.getOrElse(index) { UpdateChannel.Stable }
                        channel = next
                        result = null
                        scope.launch {
                            container.settingsRepository.setUpdateChannel(next)
                        }
                    },
                )
            }

            Text(
                text = when (channel) {
                    UpdateChannel.Stable -> "正式：Pages 镜像，与 Magisk 在线更新同源"
                    UpdateChannel.Prerelease -> "预发布：GitHub 预发布资产，不写文档站"
                    UpdateChannel.Ci -> "CI：ci-dist 分支滚动包，可能不稳定"
                },
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )

            ChargePrimaryButton(
                text = if (busy) "检查中…" else "检查更新",
                enabled = !busy,
                onClick = {
                    scope.launch {
                        busy = true
                        result = container.updateRepository.check(
                            container.statusRepository,
                            channel,
                        )
                        busy = false
                        result?.error?.let { snackbar.showSnackbar(it) }
                    }
                },
            )

            val r = result
            if (r != null) {
                val stableHint = buildString {
                    r.stableModuleNewer?.let {
                        append("正式模块 ${it.version} (${it.versionCode})")
                    }
                    r.stableAppNewer?.let {
                        if (isNotEmpty()) append("；")
                        append("正式 APP ${it.version} (${it.versionCode})")
                    }
                }
                if (stableHint.isNotEmpty()) {
                    ChargeBanner(
                        text = "正式通道有新版本：$stableHint。可切回「正式」后检查更新。",
                        tone = BannerTone.Info,
                    )
                    ChargePrimaryButton(
                        text = "切换到正式通道",
                        enabled = !busy,
                        onClick = {
                            channel = UpdateChannel.Stable
                            result = null
                            scope.launch {
                                container.settingsRepository.setUpdateChannel(UpdateChannel.Stable)
                            }
                        },
                    )
                }

                ChargeSection(title = "模块 · ${r.channel.label}") {
                    ChargeListRow(
                        title = "本地",
                        value = "${r.moduleLocal?.version ?: "未安装"} (${r.moduleLocal?.versionCode ?: 0})",
                    )
                    ChargeDivider()
                    ChargeListRow(
                        title = "远端",
                        value = "${r.moduleRemote?.version ?: "--"} (${r.moduleRemote?.versionCode ?: 0})",
                    )
                    ChargeDivider()
                    ChargeListRow(
                        title = "状态",
                        summary = when {
                            r.moduleLocal == null && r.moduleRemote != null -> "可下载安装模块"
                            r.moduleHasUpdate -> "有新版本"
                            else -> "已是最新或无法比较"
                        },
                    )
                }

                val moduleZipUrl = r.moduleRemote?.zipUrl
                val needModule = (r.moduleHasUpdate || r.moduleLocal == null) &&
                    !moduleZipUrl.isNullOrBlank()
                if (needModule && moduleZipUrl != null) {
                    ChargePrimaryButton(
                        text = if (r.moduleLocal == null) "下载并安装模块" else "下载并更新模块",
                        enabled = !busy,
                        onClick = {
                            scope.launch {
                                busy = true
                                runCatching {
                                    val file = container.updateRepository.downloadToCache(
                                        moduleZipUrl,
                                        "QSC-Battery-update.zip",
                                    )
                                    container.moduleInstallRepository.installModuleZip(file)
                                        .onSuccess { snackbar.showSnackbar("模块安装成功：$it") }
                                        .onFailure { snackbar.showSnackbar(it.message ?: "失败") }
                                }.onFailure { snackbar.showSnackbar(it.message ?: "失败") }
                                busy = false
                            }
                        },
                    )
                }

                ChargeSection(title = "APP · ${r.channel.label}") {
                    ChargeListRow(title = "本地", value = "${r.appLocalVersion} (${r.appLocalCode})")
                    ChargeDivider()
                    ChargeListRow(
                        title = "远端",
                        value = "${r.appRemote?.version ?: "--"} (${r.appRemote?.versionCode ?: 0})",
                    )
                    ChargeDivider()
                    ChargeListRow(
                        title = "状态",
                        summary = if (r.appHasUpdate) "有新版本" else "已是最新或无法比较",
                    )
                }

                val appApkUrl = r.appRemote?.apkUrl
                if (!appApkUrl.isNullOrBlank()) {
                    ChargePrimaryButton(
                        text = if (r.appHasUpdate) "下载并安装 APP" else "重新下载安装 APP",
                        enabled = !busy,
                        onClick = {
                            scope.launch {
                                busy = true
                                runCatching {
                                    val file = container.updateRepository.downloadToCache(
                                        appApkUrl,
                                        "QSC-Battery.apk",
                                    )
                                    container.moduleInstallRepository.promptInstallApk(file)
                                    snackbar.showSnackbar("已打开系统安装界面")
                                }.onFailure { snackbar.showSnackbar(it.message ?: "失败") }
                                busy = false
                            }
                        },
                    )
                } else {
                    r.error?.let { err ->
                        ChargeBanner(text = err, tone = BannerTone.Warn)
                    }
                }
            }
        }
    }
}
