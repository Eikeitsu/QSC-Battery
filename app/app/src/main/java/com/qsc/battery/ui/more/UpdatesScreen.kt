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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTopBar
import kotlinx.coroutines.launch

@Composable
fun UpdatesScreen(
    container: AppContainer,
    onBack: () -> Unit,
    snackbar: SnackbarHostState,
) {
    var result by remember { mutableStateOf<UpdateCheckResult?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(title = "更新", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
                .padding(
                    top = ChargeTheme.dimens.topBarContentGap,
                    bottom = ChargeTheme.dimens.sectionGap,
                ),
            verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
        ) {
            Text(
                text = "检查模块与伴侣 APP 的远端版本，并一键下载安装。",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )

            ChargePrimaryButton(
                text = if (busy) "检查中…" else "检查更新",
                enabled = !busy,
                onClick = {
                    scope.launch {
                        busy = true
                        result = container.updateRepository.check(container.statusRepository)
                        busy = false
                        result?.error?.let { snackbar.showSnackbar(it) }
                    }
                },
            )

            val r = result
            if (r != null) {
                ChargeSection(title = "模块") {
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

                val needModule = (r.moduleHasUpdate || r.moduleLocal == null) &&
                    !r.moduleRemote?.zipUrl.isNullOrBlank()
                if (needModule) {
                    ChargePrimaryButton(
                        text = if (r.moduleLocal == null) "下载并安装模块" else "下载并更新模块",
                        enabled = !busy,
                        onClick = {
                            scope.launch {
                                busy = true
                                runCatching {
                                    val file = container.updateRepository.downloadToCache(
                                        r.moduleRemote!!.zipUrl!!,
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

                ChargeSection(title = "APP") {
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

                if (!r.appRemote?.apkUrl.isNullOrBlank()) {
                    ChargePrimaryButton(
                        text = if (r.appHasUpdate) "下载并安装 APP" else "重新下载安装 APP",
                        enabled = !busy,
                        onClick = {
                            scope.launch {
                                busy = true
                                runCatching {
                                    val file = container.updateRepository.downloadToCache(
                                        r.appRemote!!.apkUrl!!,
                                        "QSC-Battery.apk",
                                    )
                                    container.moduleInstallRepository.promptInstallApk(file)
                                    snackbar.showSnackbar("已打开系统安装界面")
                                }.onFailure { snackbar.showSnackbar(it.message ?: "失败") }
                                busy = false
                            }
                        },
                    )
                } else if (r.error != null) {
                    ChargeBanner(text = r.error!!, tone = BannerTone.Warn)
                }
            }
        }
    }
}
