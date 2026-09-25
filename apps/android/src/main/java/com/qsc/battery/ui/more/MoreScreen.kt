package com.qsc.battery.ui.more

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qsc.battery.BuildConfig
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.AppViewModelFactory
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargeScreen
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.ui.util.LifecycleResumeEffect
import com.qsc.battery.xposed.XpRuntime

@Composable
fun MoreScreen(
    container: AppContainer,
    onOpenAppearance: () -> Unit,
    onOpenUpdates: () -> Unit,
    onOpenProfiles: () -> Unit,
    onOpenXp: () -> Unit,
    snackbar: SnackbarHostState,
) {
    val factory = remember(container) { AppViewModelFactory(container) }
    val vm: MoreViewModel = viewModel(factory = factory)
    val ui by vm.ui.collectAsStateWithLifecycle()
    var tileSheet by remember { mutableStateOf(false) }

    LifecycleResumeEffect { vm.refreshMeta() }

    val permHint = ui.permHint
    val xpStatus = ui.xpStatus

    ChargeScreen(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            ChargeTopBar(
                title = "我的",
                subtitle = "v${BuildConfig.VERSION_NAME}",
            )
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
        ) {
            val chips = buildList {
                add(if (permHint.contains("Root ✓")) "Root ✓" else "Root ✗")
                add(if (permHint.contains("模块 ✓")) "模块 ✓" else "模块 ✗")
                add(
                    when (xpStatus?.level) {
                        XpRuntime.Level.Active -> "XP 已运行"
                        XpRuntime.Level.Enabled -> "XP 已启用"
                        XpRuntime.Level.Framework -> "XP 未启用"
                        XpRuntime.Level.ManagerOnly -> "XP 仅管理器"
                        else -> "XP 未检测"
                    },
                )
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.horizontalScroll(rememberScrollState()),
            ) {
                chips.forEach { chip ->
                    val ok = chip.contains("✓") || chip.contains("已运行") || chip.contains("已启用")
                    val warn = chip.contains("仅管理器") || chip.contains("未启用")
                    val tone = when {
                        ok -> ChargeTheme.colors.accent
                        warn -> ChargeTheme.colors.accent
                        else -> ChargeTheme.colors.danger
                    }
                    val fill = when {
                        ok -> ChargeTheme.colors.accent.copy(alpha = 0.16f)
                        warn -> ChargeTheme.colors.accent.copy(alpha = 0.10f)
                        else -> ChargeTheme.colors.danger.copy(alpha = 0.12f)
                    }
                    Surface(
                        shape = RoundedCornerShape(999.dp),
                        color = fill,
                        border = BorderStroke(1.dp, tone.copy(alpha = if (ok) 0.55f else 0.40f)),
                    ) {
                        Text(
                            text = chip,
                            style = ChargeTheme.typography.caption,
                            color = if (ok || warn) tone else ChargeTheme.colors.danger,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
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

            ChargeSection(title = "排障") {
                ChargeToggleRow(
                    title = "详细调试日志",
                    checked = ui.debugOn,
                    summary = "写入 log.log：插电/停充/涓流/电流/qscd 等；随开随关，日常请关",
                    onCheckedChange = { vm.setDebugOn(it) },
                )
                ChargeDivider()
                ChargeListRow(
                    title = if (ui.exporting) "正在打包日志…" else "导出日志",
                    summary = "打包 zip（log / 事件 / XP / 配置）并用系统分享发出",
                    onClick = {
                        if (!ui.exporting) {
                            vm.exportLogs { snackbar.showSnackbar(it) }
                        }
                    },
                )
            }

            ChargeSection(title = "权限与增强") {
                ChargeListRow(
                    title = "重新检测权限",
                    summary = permHint.ifBlank { "Root / 通知 / 安装包 / XP" },
                    onClick = {
                        vm.requestReOnboarding {
                            snackbar.showSnackbar("下次启动将重新进入引导")
                        }
                    },
                )
                ChargeDivider()
                ChargeListRow(
                    title = "LSPosed / XP",
                    summary = xpStatus?.detail
                        ?: "可选：作用域勾选系统框架(system)；管理器前台刷简介 + qscd 降级时插拔唤醒",
                    onClick = onOpenXp,
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
