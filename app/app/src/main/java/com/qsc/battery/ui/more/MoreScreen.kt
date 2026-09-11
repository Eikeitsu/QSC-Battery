package com.qsc.battery.ui.more

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.PermStatus
import com.qsc.battery.core.PermissionChecker
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePage
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import com.qsc.battery.xposed.XpRuntime
import kotlinx.coroutines.launch

@Composable
fun MoreScreen(
    container: AppContainer,
    onOpenAppearance: () -> Unit,
    onOpenUpdates: () -> Unit,
    onOpenProfiles: () -> Unit,
    snackbar: SnackbarHostState,
) {
    var permHint by remember { mutableStateOf("") }
    var xpStatus by remember { mutableStateOf<XpRuntime.Status?>(null) }
    var tileSheet by remember { mutableStateOf(false) }
    val xpEnabled by container.settingsRepository.xpPowerEventsEnabled.collectAsStateWithLifecycle(initialValue = true)
    val scope = rememberCoroutineScope()
    val checker = remember { PermissionChecker(container.appContext) }

    suspend fun refreshMeta() {
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

    ChargePage(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        Text(
            text = "我的",
            style = ChargeTheme.typography.title,
            color = ChargeTheme.colors.ink,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "v${BuildConfig.VERSION_NAME}",
            style = ChargeTheme.typography.caption,
            color = ChargeTheme.colors.muted,
        )

        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.horizontalScroll(rememberScrollState()),
        ) {
            permHint.split(Regex("\\s{2,}")).filter { it.isNotBlank() }.forEach { chip ->
                Surface(
                    shape = RoundedCornerShape(999.dp),
                    color = ChargeTheme.colors.surfaceStrong,
                ) {
                    Text(
                        text = chip.trim(),
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.ink,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                }
            }
        }

        ChargeSection(title = "工具箱") {
            ChargeListRow(
                title = "主题与颜色",
                summary = "浅色 / 深色 / AMOLED / 调色板",
                onClick = onOpenAppearance,
            )
            ChargeDivider()
            ChargeListRow(
                title = "更新与安装",
                summary = "检查模块与 APP 更新",
                onClick = onOpenUpdates,
            )
            ChargeDivider()
            ChargeListRow(
                title = "配置档",
                summary = "档位管理与 JSON 导入导出",
                onClick = onOpenProfiles,
            )
        }

        ChargeSection(title = "权限与增强") {
            ChargeListRow(
                title = "重新检测权限",
                summary = permHint.ifBlank { "Root / 通知 / 安装包 / XP" },
                onClick = {
                    scope.launch {
                        container.settingsRepository.setOnboardingDone(false)
                        snackbar.showSnackbar("下次启动将重新进入引导")
                    }
                },
            )
            ChargeDivider()
            ChargeToggleRow(
                title = "XP 供电事件补强",
                checked = xpEnabled,
                summary = xpStatus?.detail
                    ?: "需安装并启用 LSPosed，作用域勾选系统框架(android)",
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
            ChargeDivider()
            ChargeListRow(
                title = "快捷设置磁贴",
                summary = "添加系统磁贴以切换模块软开关",
                onClick = { tileSheet = true },
            )
        }

        ChargeSection(title = "关于") {
            ChargeListRow(title = "版本", value = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            ChargeDivider()
            ChargeListRow(title = "包名", summary = BuildConfig.APPLICATION_ID)
            ChargeDivider()
            ChargeListRow(title = "模块 ID", value = BuildConfig.MODULE_ID)
            ChargeDivider()
            ChargeListRow(
                title = "说明",
                summary = "底层由 Magisk 模块执行；本应用仅配置与展示。",
            )
        }
    }

    if (tileSheet) {
        AlertDialog(
            onDismissRequest = { tileSheet = false },
            title = { Text("快捷设置磁贴") },
            text = {
                Text("在系统「编辑磁贴」中添加「充电控制」。点击磁贴可切换模块软开关（需 Root）。")
            },
            confirmButton = {
                TextButton(onClick = { tileSheet = false }) { Text("知道了") }
            },
        )
    }
}
