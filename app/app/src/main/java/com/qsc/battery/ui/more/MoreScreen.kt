package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.moriafly.salt.ui.Item
import com.moriafly.salt.ui.ItemOuterTitle
import com.moriafly.salt.ui.ItemSwitcher
import com.moriafly.salt.ui.ItemValue
import com.moriafly.salt.ui.RoundedColumn
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text
import com.moriafly.salt.ui.UnstableSaltUiApi
import com.moriafly.salt.ui.dialog.InputDialog
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.PermStatus
import com.qsc.battery.core.PermissionChecker
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.AppPage
import com.qsc.battery.ui.design.AppPrimaryButton
import com.qsc.battery.ui.design.AppSecondaryButton
import com.qsc.battery.xposed.XpRuntime
import kotlinx.coroutines.launch

@OptIn(UnstableSaltUiApi::class)
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
    var editingProfile by remember { mutableStateOf(false) }
    var editingBundle by remember { mutableStateOf(false) }
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

    AppPage(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        Text(
            text = "我的",
            style = SaltTheme.textStyles.main,
            fontWeight = FontWeight.SemiBold,
        )
        message?.let {
            Text(text = it, color = SaltTheme.colors.highlight, style = SaltTheme.textStyles.sub)
        }

        ItemOuterTitle(text = "外观")
        RoundedColumn {
            Item(
                onClick = onOpenAppearance,
                text = "主题与颜色",
                sub = "浅色 / 深色 / 动态取色 / 调色板",
            )
        }

        ItemOuterTitle(text = "权限与增强")
        RoundedColumn {
            Item(
                onClick = {
                    scope.launch {
                        container.settingsRepository.setOnboardingDone(false)
                        onOpenOnboarding()
                    }
                },
                text = "重新检测权限",
                sub = permHint.ifBlank { "Root / 通知 / 安装包 / XP" },
            )
            ItemSwitcher(
                state = xpEnabled,
                onChange = { enabled ->
                    scope.launch {
                        container.settingsRepository.setXpPowerEvents(enabled)
                        if (container.root.isRootAvailable()) {
                            if (enabled) container.root.rm("/data/adb/qsc/xp_power_events_off")
                            else container.root.exec("mkdir -p /data/adb/qsc; touch /data/adb/qsc/xp_power_events_off")
                        }
                        refreshMeta()
                    }
                },
                text = "XP 供电事件补强",
                sub = xpStatus?.detail
                    ?: "需安装并启用 LSPosed，作用域勾选系统框架(android)",
            )
            Item(
                onClick = {},
                text = "快捷设置磁贴",
                sub = "在系统「编辑磁贴」中添加「充电控制」；点击切换模块软开关（需 Root）",
            )
        }

        ItemOuterTitle(text = "更新与安装")
        RoundedColumn {
            Item(
                onClick = onOpenUpdates,
                text = "检查 / 安装 APP 与模块更新",
                sub = "无模块时也可检查并下载模块 zip",
            )
            Item(
                onClick = {
                    scope.launch {
                        message = container.moduleInstallRepository.installCompanionApkOnline()
                            .fold({ "APP 已安装 / 已打开安装界面" }, { it.message ?: "下载或安装失败" })
                    }
                },
                text = "在线下载并安装 APP",
            )
        }

        ItemOuterTitle(text = "配置档")
        RoundedColumn {
            Item(
                onClick = { editingProfile = true },
                text = "档位名称",
                tag = profileName.ifBlank { "点击填写" },
            )
            profiles.forEach { name ->
                Item(
                    onClick = {
                        scope.launch {
                            val ok = container.profilesRepository.applyProfile(name, container.configRepository)
                            message = if (ok) "已应用 $name" else "应用失败"
                        }
                    },
                    text = name,
                    sub = "点击应用",
                )
            }
        }
        AppPrimaryButton(
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

        ItemOuterTitle(text = "导入 / 导出")
        RoundedColumn {
            Item(
                onClick = {
                    scope.launch {
                        bundleText = container.profilesRepository.exportBundle().orEmpty()
                        message = if (bundleText.isNotBlank()) "已导出，可点击下方编辑/导入" else "导出失败"
                    }
                },
                text = "导出配置包",
            )
            Item(
                onClick = { editingBundle = true },
                text = "配置 JSON",
                sub = if (bundleText.isBlank()) "点击粘贴或编辑" else "已载入 ${bundleText.length} 字符",
            )
        }
        AppSecondaryButton(
            text = "导入配置包",
            onClick = {
                scope.launch {
                    val ok = container.profilesRepository.importBundle(bundleText, container.configRepository)
                    message = if (ok) "导入成功" else "导入失败"
                }
            },
        )

        ItemOuterTitle(text = "关于")
        RoundedColumn {
            ItemValue(text = "版本", sub = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            ItemValue(text = "包名", sub = BuildConfig.APPLICATION_ID)
            ItemValue(text = "模块 ID", sub = BuildConfig.MODULE_ID)
            ItemValue(text = "说明", sub = "底层由 Magisk 模块执行；本应用仅配置与展示。")
        }
    }

    if (editingProfile) {
        InputDialog(
            onDismissRequest = { editingProfile = false },
            onConfirm = { editingProfile = false },
            title = "档位名称",
            text = profileName,
            onChange = { profileName = it },
            hint = "例如：日常 / 出行",
        )
    }
    if (editingBundle) {
        InputDialog(
            onDismissRequest = { editingBundle = false },
            onConfirm = { editingBundle = false },
            title = "配置 JSON",
            text = bundleText,
            onChange = { bundleText = it },
            hint = "粘贴导出的 JSON",
        )
    }
}
