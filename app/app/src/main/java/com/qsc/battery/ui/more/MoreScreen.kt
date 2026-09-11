package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier.modifier
import androidx.compose.ui.unit.dp
import com.qsc.battery.BuildConfig
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.components.PrefAction
import com.qsc.battery.ui.components.PrefCard
import com.qsc.battery.ui.components.SectionLabel
import kotlinx.coroutines.launch

@Composable
fun MoreScreen(
    container: AppContainer,
    onOpenAppearance: () -> Unit,
    onOpenUpdates: () -> Unit,
) {
    var profiles by remember { mutableStateOf<List<String>>(emptyList()) }
    var profileName by remember { mutableStateOf("") }
    var bundleText by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        profiles = container.profilesRepository.listNames()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("更多", style = MaterialTheme.typography.headlineSmall)
        message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }

        SectionLabel("外观")
        PrefCard {
            PrefAction("主题与界面风格", "对齐 SukiSU：MIUIX / Material 3") { onOpenAppearance() }
        }

        SectionLabel("更新与安装")
        PrefCard {
            PrefAction("检查 / 安装 APP 与模块更新", "无模块时也可检查并下载模块 zip") { onOpenUpdates() }
            PrefAction("从已刷模块目录安装内置 APP（可选）") {
                scope.launch {
                    message = container.moduleInstallRepository.installBundledApkFromModule()
                        .fold({ "APP 已安装" }, { it.message ?: "失败（可能未刷入带 APK 的模块包）" })
                }
            }
        }

        SectionLabel("配置档")
        PrefCard {
            OutlinedTextField(
                value = profileName,
                onValueChange = { profileName = it },
                label = { Text("档位名称") },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                singleLine = true,
            )
            Button(
                onClick = {
                    scope.launch {
                        val conf = container.configRepository.loadConf()
                        val current = container.root.readFile(com.qsc.battery.core.ModulePaths.CURRENT)
                        val ok = container.profilesRepository.saveProfile(profileName.trim(), conf, current)
                        profiles = container.profilesRepository.listNames()
                        message = if (ok) "已保存档位" else "保存失败"
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                enabled = profileName.isNotBlank(),
            ) { Text("保存当前为档位") }

            profiles.forEach { name ->
                PrefAction(name, "点击应用") {
                    scope.launch {
                        val ok = container.profilesRepository.applyProfile(name, container.configRepository)
                        message = if (ok) "已应用 $name" else "应用失败"
                    }
                }
            }
        }

        SectionLabel("导入 / 导出")
        PrefCard {
            Button(
                onClick = {
                    scope.launch {
                        bundleText = container.profilesRepository.exportBundle().orEmpty()
                        message = if (bundleText.isNotBlank()) "已导出到下方文本" else "导出失败"
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) { Text("导出配置包") }
            OutlinedTextField(
                value = bundleText,
                onValueChange = { bundleText = it },
                label = { Text("配置 JSON") },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                minLines = 4,
            )
            Button(
                onClick = {
                    scope.launch {
                        val ok = container.profilesRepository.importBundle(bundleText, container.configRepository)
                        message = if (ok) "导入成功" else "导入失败"
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) { Text("导入配置包") }
        }

        SectionLabel("关于")
        PrefCard {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("QSC Battery ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
                Text("包名 ${BuildConfig.APPLICATION_ID}")
                Text("模块 ID ${BuildConfig.MODULE_ID}")
                Text("底层由 Magisk 模块执行；本 APP 仅配置与展示，不挂后台。")
            }
        }
    }
}
