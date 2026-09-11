package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.PermStatus
import com.qsc.battery.core.PermissionChecker
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.PrefAction
import com.qsc.battery.ui.design.PrefSwitch
import com.qsc.battery.ui.design.VoltPage
import com.qsc.battery.ui.design.VoltPrimaryButton
import com.qsc.battery.ui.design.VoltSection
import com.qsc.battery.ui.design.VoltSectionLabel
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
    var xpStatus by remember { mutableStateOf<XpRuntime.Status?>(null) }
    val xpEnabled by container.settingsRepository.xpPowerEventsEnabled.collectAsStateWithLifecycle(initialValue = true)
    val scope = rememberCoroutineScope()
    val checker = remember { PermissionChecker(container.appContext) }

    suspend fun refreshMeta() {
        profiles = container.profilesRepository.listNames()
        val st = container.statusRepository.load()
        val snap = checker.snapshot(st.modulePresent)
        xpStatus = XpRuntime.probe(container.appContext, container.root)
        permHint = buildString {
            append(if (snap.root == PermStatus.Ok) "Root ✓  " else "Root ✗  ")
            append(if (snap.notifications == PermStatus.Ok) "通知 ✓  " else "通知 ✗  ")
            append(if (snap.installPackages == PermStatus.Ok) "安装 ✓  " else "安装 ✗  ")
            append(
                when (xpStatus?.level) {
                    XpRuntime.Level.Injected -> "XP 注入 ✓"
                    XpRuntime.Level.Framework -> "XP 框架 ○"
                    XpRuntime.Level.ManagerOnly -> "XP 管理器 ○"
                    else -> "XP ✗"
                },
            )
        }
        if (container.root.isRootAvailable()) {
            val off = container.root.exists("/data/adb/qsc/xp_power_events_off")
            container.settingsRepository.setXpPowerEvents(!off)
        }
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) scope.launch { refreshMeta() }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    VoltPage(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text("我的", style = MaterialTheme.typography.headlineSmall)
        message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }

        VoltSectionLabel("外观")
        VoltSection {
            PrefAction("主题与颜色", "浅色 / 深色 / 动态取色 / 调色板", onClick = onOpenAppearance)
        }

        VoltSectionLabel("权限与增强")
        VoltSection {
            PrefAction("重新检测权限", permHint.ifBlank { "Root / 通知 / 安装包 / XP" }) {
                scope.launch {
                    container.settingsRepository.setOnboardingDone(false)
                    onOpenOnboarding()
                }
            }
            PrefSwitch(
                title = "XP 供电事件补强",
                summary = xpStatus?.detail
                    ?: "需安装并启用 LSPosed，作用域勾选系统框架(android)",
                checked = xpEnabled,
                onCheckedChange = { enabled ->
                    scope.launch {
                        container.settingsRepository.setXpPowerEvents(enabled)
                        if (container.root.isRootAvailable()) {
                            if (enabled) container.root.rm("/data/adb/qsc/xp_power_events_off")
                            else container.root.exec("mkdir -p /data/adb/qsc; touch /data/adb/qsc/xp_power_events_off")
                        }
                        refreshMeta()
                    }
                },
            )
            PrefAction(
                title = "快捷设置磁贴",
                summary = "在系统「编辑磁贴」中添加「充电控制」；点击切换模块软开关（需 Root）",
            ) {}
        }

        VoltSectionLabel("更新与安装")
        VoltSection {
            PrefAction("检查 / 安装 APP 与模块更新", "无模块时也可检查并下载模块 zip") { onOpenUpdates() }
            PrefAction("在线下载并安装 APP") {
                scope.launch {
                    message = container.moduleInstallRepository.installCompanionApkOnline()
                        .fold({ "APP 已安装 / 已打开安装界面" }, { it.message ?: "下载或安装失败" })
                }
            }
        }

        VoltSectionLabel("配置档")
        VoltSection {
            OutlinedTextField(
                value = profileName,
                onValueChange = { profileName = it },
                label = { Text("档位名称") },
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                singleLine = true,
            )
            Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                VoltPrimaryButton(
                    text = "保存当前为档位",
                    enabled = profileName.isNotBlank(),
                    onClick = {
                        scope.launch {
                            val conf = container.configRepository.loadConf()
                            val current = container.root.readFile(ModulePaths.CURRENT)
                            val ok = container.profilesRepository.saveProfile(profileName.trim(), conf, current)
                            profiles = container.profilesRepository.listNames()
                            message = if (ok) "已保存档位" else "保存失败"
                        }
                    },
                )
            }
            profiles.forEach { name ->
                PrefAction(name, "点击应用") {
                    scope.launch {
                        val ok = container.profilesRepository.applyProfile(name, container.configRepository)
                        message = if (ok) "已应用 $name" else "应用失败"
                    }
                }
            }
        }

        VoltSectionLabel("导入 / 导出")
        VoltSection {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                VoltPrimaryButton(
                    text = "导出配置包",
                    onClick = {
                        scope.launch {
                            bundleText = container.profilesRepository.exportBundle().orEmpty()
                            message = if (bundleText.isNotBlank()) "已导出到下方文本" else "导出失败"
                        }
                    },
                )
                OutlinedTextField(
                    value = bundleText,
                    onValueChange = { bundleText = it },
                    label = { Text("配置 JSON") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 4,
                )
                VoltPrimaryButton(
                    text = "导入配置包",
                    onClick = {
                        scope.launch {
                            val ok = container.profilesRepository.importBundle(bundleText, container.configRepository)
                            message = if (ok) "导入成功" else "导入失败"
                        }
                    },
                )
            }
        }

        VoltSectionLabel("关于")
        VoltSection {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("充电控制 ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
                Text("包名 ${BuildConfig.APPLICATION_ID}")
                Text("模块 ID ${BuildConfig.MODULE_ID}")
                Text("底层由 Magisk 模块执行；本应用仅配置与展示。")
            }
        }
    }
}
