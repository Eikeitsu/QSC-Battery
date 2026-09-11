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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.PermStatus
import com.qsc.battery.core.PermissionChecker
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.components.PrefAction
import com.qsc.battery.ui.components.PrefCard
import com.qsc.battery.ui.components.PrefSwitch
import com.qsc.battery.ui.components.SectionLabel
import com.qsc.battery.xposed.XpRuntime
import kotlinx.coroutines.launch

@Composable
fun MoreScreen(
    container: AppContainer,
    onOpenAppearance: () -> Unit,
    onOpenUpdates: () -> Unit,
    onOpenOnboarding: () -> Unit = {},
) {
    var profiles by remember { mutableStateOf<List<String>>(emptyList()) }
    var profileName by remember { mutableStateOf("") }
    var bundleText by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var permHint by remember { mutableStateOf("") }
    val xpEnabled by container.settingsRepository.xpPowerEventsEnabled.collectAsStateWithLifecycle(true)
    val scope = rememberCoroutineScope()
    val checker = remember { PermissionChecker(container.appContext) }

    LaunchedEffect(Unit) {
        profiles = container.profilesRepository.listNames()
        val st = container.statusRepository.load()
        val snap = checker.snapshot(st.modulePresent)
        permHint = buildString {
            append(if (snap.root == PermStatus.Ok) "Root ✓  " else "Root ✗  ")
            append(if (snap.notifications == PermStatus.Ok) "通知 ✓  " else "通知 ✗  ")
            append(if (snap.installPackages == PermStatus.Ok) "安装 ✓  " else "安装 ✗  ")
            append(if (XpRuntime.isAvailable(container.appContext)) "XP ✓" else "XP ○")
        }
        // 用设备上的关闭标记对齐 DataStore（XP 侧只认文件）
        if (container.root.isRootAvailable()) {
            val off = container.root.exists("/data/adb/qsc/xp_power_events_off")
            container.settingsRepository.setXpPowerEvents(!off)
        }
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
            PrefAction("主题与界面风格", "MIUIX / Material 3、颜色与调色板") { onOpenAppearance() }
        }

        SectionLabel("权限与增强")
        PrefCard {
            PrefAction("重新检测权限", permHint.ifBlank { "Root / 通知 / 安装包 / XP" }) {
                scope.launch {
                    container.settingsRepository.setOnboardingDone(false)
                    onOpenOnboarding()
                }
            }
            PrefSwitch(
                title = "XP 供电事件补强",
                summary = if (XpRuntime.isAvailable(container.appContext)) {
                    "LSPosed API 102；开启后由系统侧写入提示文件"
                } else {
                    "需安装并启用 LSPosed，作用域勾选系统框架(android)"
                },
                checked = xpEnabled,
                onCheckedChange = { enabled ->
                    scope.launch {
                        container.settingsRepository.setXpPowerEvents(enabled)
                        if (container.root.isRootAvailable()) {
                            if (enabled) {
                                container.root.rm("/data/adb/qsc/xp_power_events_off")
                            } else {
                                container.root.exec(
                                    "mkdir -p /data/adb/qsc; touch /data/adb/qsc/xp_power_events_off",
                                )
                            }
                        }
                    }
                },
            )
            PrefAction(
                title = "快捷设置磁贴",
                summary = "在系统「编辑磁贴」中添加「充电控制」；点击切换模块软开关（需 Root）",
            ) {}
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
                        val current = container.root.readFile(ModulePaths.CURRENT)
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
                Text("充电控制 ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
                Text("包名 ${BuildConfig.APPLICATION_ID}")
                Text("模块 ID ${BuildConfig.MODULE_ID}")
                Text("底层由 Magisk 模块执行；本应用仅配置与展示，不挂后台保活。")
                Text("可选 LSPosed 增强不参与节点写入。")
            }
        }
    }
}
