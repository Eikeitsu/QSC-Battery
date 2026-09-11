package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier.modifier
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.AppContainer
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.ui.components.PrefCard
import com.qsc.battery.ui.components.SectionLabel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpdatesScreen(
    container: AppContainer,
    onBack: () -> Unit,
) {
    var result by remember { mutableStateOf<UpdateCheckResult?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("更新") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Button(
                onClick = {
                    scope.launch {
                        busy = true
                        message = null
                        result = container.updateRepository.check(container.statusRepository)
                        busy = false
                    }
                },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (busy) "检查中…" else "检查更新") }

            message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
            result?.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }

            val r = result
            if (r != null) {
                SectionLabel("模块")
                PrefCard {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("本地 ${r.moduleLocal?.version ?: "未安装"} (${r.moduleLocal?.versionCode ?: 0})")
                        Text("远端 ${r.moduleRemote?.version ?: "--"} (${r.moduleRemote?.versionCode ?: 0})")
                        Text(
                            when {
                                r.moduleLocal == null && r.moduleRemote != null -> "可下载安装模块"
                                r.moduleHasUpdate -> "有新版本"
                                else -> "已是最新或无法比较"
                            },
                        )
                        if ((r.moduleHasUpdate || r.moduleLocal == null) && !r.moduleRemote?.zipUrl.isNullOrBlank()) {
                            Button(
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
                                modifier = Modifier.fillMaxWidth(),
                                enabled = !busy,
                            ) { Text(if (r.moduleLocal == null) "下载并安装模块" else "下载并更新模块") }
                        }
                    }
                }

                SectionLabel("APP")
                PrefCard {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("本地 ${r.appLocalVersion} (${r.appLocalCode})")
                        Text("远端 ${r.appRemote?.version ?: "--"} (${r.appRemote?.versionCode ?: 0})")
                        Text(if (r.appHasUpdate) "有新版本" else "已是最新或无法比较")
                        if (r.appHasUpdate && !r.appRemote?.apkUrl.isNullOrBlank()) {
                            Button(
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
                                modifier = Modifier.fillMaxWidth(),
                                enabled = !busy,
                            ) { Text("下载并安装 APP") }
                        }
                    }
                }
            }
        }
    }
}
