package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import com.moriafly.salt.ui.ItemOuterTitle
import com.moriafly.salt.ui.ItemValue
import com.moriafly.salt.ui.RoundedColumn
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text
import com.moriafly.salt.ui.UnstableSaltUiApi
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.ui.design.AppPage
import com.qsc.battery.ui.design.AppTitleBar
import com.qsc.battery.ui.design.AppPrimaryButton
import kotlinx.coroutines.launch

@OptIn(UnstableSaltUiApi::class)
@Composable
fun UpdatesScreen(
    container: AppContainer,
    onBack: () -> Unit,
) {
    var result by remember { mutableStateOf<UpdateCheckResult?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        AppTitleBar(title = "更新", onBack = onBack)
        AppPage(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            includeStatusSpacer = false,
        ) {
            AppPrimaryButton(
                text = if (busy) "检查中…" else "检查更新",
                enabled = !busy,
                onClick = {
                    scope.launch {
                        busy = true
                        message = null
                        result = container.updateRepository.check(container.statusRepository)
                        busy = false
                    }
                },
            )

            message?.let {
                Text(text = it, color = SaltTheme.colors.highlight, style = SaltTheme.textStyles.sub)
            }
            result?.error?.let {
                Text(text = it, color = Color(0xFFB3261E), style = SaltTheme.textStyles.sub)
            }

            val r = result
            if (r != null) {
                ItemOuterTitle(text = "模块")
                RoundedColumn {
                    ItemValue(
                        text = "本地",
                        sub = "${r.moduleLocal?.version ?: "未安装"} (${r.moduleLocal?.versionCode ?: 0})",
                    )
                    ItemValue(
                        text = "远端",
                        sub = "${r.moduleRemote?.version ?: "--"} (${r.moduleRemote?.versionCode ?: 0})",
                    )
                    ItemValue(
                        text = "状态",
                        sub = when {
                            r.moduleLocal == null && r.moduleRemote != null -> "可下载安装模块"
                            r.moduleHasUpdate -> "有新版本"
                            else -> "已是最新或无法比较"
                        },
                    )
                }
                if ((r.moduleHasUpdate || r.moduleLocal == null) && !r.moduleRemote?.zipUrl.isNullOrBlank()) {
                    AppPrimaryButton(
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
                                        .onSuccess { message = "模块安装成功：$it（若提示重启请重启）" }
                                        .onFailure { message = it.message }
                                }.onFailure { message = it.message }
                                busy = false
                            }
                        },
                    )
                }

                ItemOuterTitle(text = "APP")
                RoundedColumn {
                    ItemValue(text = "本地", sub = "${r.appLocalVersion} (${r.appLocalCode})")
                    ItemValue(
                        text = "远端",
                        sub = "${r.appRemote?.version ?: "--"} (${r.appRemote?.versionCode ?: 0})",
                    )
                    ItemValue(
                        text = "状态",
                        sub = if (r.appHasUpdate) "有新版本" else "已是最新或无法比较",
                    )
                }
                if (!r.appRemote?.apkUrl.isNullOrBlank()) {
                    AppPrimaryButton(
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
                                    message = "已打开系统安装界面"
                                }.onFailure { message = it.message }
                                busy = false
                            }
                        },
                    )
                }
            }
        }
    }
}
