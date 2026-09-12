package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.AppViewModelFactory
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.ui.util.LifecycleResumeEffect

@Composable
fun XpPanelScreen(
    container: AppContainer,
    onBack: () -> Unit,
    onOpenLspLog: () -> Unit,
    snackbar: SnackbarHostState,
) {
    val factory = remember(container) { AppViewModelFactory(container) }
    val vm: XpPanelViewModel = viewModel(factory = factory)
    val ui by vm.ui.collectAsStateWithLifecycle()
    val status = ui.status
    val toggles = ui.toggles
    val busy = ui.busy

    LifecycleResumeEffect { vm.refresh() }
    LaunchedEffect(ui.message) {
        ui.message?.let {
            snackbar.showSnackbar(it)
            vm.consumeMessage()
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(
            title = "LSPosed / XP",
            subtitle = "边沿唤醒辅助 · 不停充",
            onBack = onBack,
        )
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
                text = "① 服务连接（打开本页即可）→ ② 作用域含 system → ③ 重启后框架注入。" +
                    "停充始终由 Magisk 执行。",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )

            ChargeSection(title = "状态") {
                ChargeListRow(
                    title = "总览",
                    summary = status?.detail ?: "检测中…",
                )
                ChargeDivider()
                ChargeListRow(
                    title = "① 服务",
                    value = if (status?.serviceBound == true) "已连接" else "未连接",
                )
                ChargeDivider()
                ChargeListRow(
                    title = "② 作用域",
                    summary = when {
                        status?.scopedAndroid == true -> "含系统框架 (system)"
                        status?.scopeKnown == true ->
                            "未含 system：${status.scopeList.joinToString().ifBlank { "空" }}"
                        else -> "未知（服务未连接时无法即时读取）"
                    },
                )
                ChargeDivider()
                ChargeListRow(
                    title = "③ 注入",
                    value = if (status?.frameworkAlive == true) "已注入" else "未注入",
                    summary = if (status?.frameworkAlive == true) {
                        "存活标记或 runningTargets 已确认"
                    } else {
                        "需启用模块、勾选系统框架后重启"
                    },
                )
                ChargeDivider()
                ChargeListRow(
                    title = "框架",
                    summary = listOfNotNull(
                        status?.frameworkName,
                        status?.frameworkVersion,
                        status?.apiVersion?.let { "API $it" },
                    ).joinToString(" · ").ifBlank { "—" },
                )
                ChargeDivider()
                ChargeListRow(
                    title = "运行目标",
                    summary = status?.runningTargets?.joinToString()?.ifBlank { "无 / 需 API 102" } ?: "—",
                )
                ChargeDivider()
                ChargeListRow(
                    title = "Magisk 武装",
                    value = when {
                        status?.xpOffFile == true -> "软关闭中"
                        status?.armed == true -> "已武装 (qscd 不可用)"
                        else -> "未武装"
                    },
                )
            }

            ChargeSection(title = "作用域") {
                ChargePrimaryButton(
                    text = if (busy) "请求中…" else "一键请求系统框架 (system)",
                    enabled = !busy && status?.serviceBound == true,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { vm.requestSystemScope() },
                )
                Text(
                    text = "与 HyperCeiler 相同：走 XposedService.requestScope，无需为读/改作用域重启。",
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.muted,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }

            ChargeSection(title = "开关") {
                ChargeToggleRow(
                    title = "允许边沿唤醒",
                    checked = toggles.wakeEnabled && !toggles.xpOff,
                    summary = "qscd 不可用且已武装时，插拔边沿写唤醒文件",
                    enabled = !busy,
                    onCheckedChange = { vm.setWakeEnabled(it) },
                )
                ChargeDivider()
                ChargeToggleRow(
                    title = "软关闭 XP",
                    checked = toggles.xpOff,
                    summary = "touch /data/system/qsc_xp_off；Magisk 与 XP 均尊重",
                    enabled = !busy,
                    onCheckedChange = { vm.setXpOff(it) },
                )
                ChargeDivider()
                ChargeToggleRow(
                    title = "详细日志",
                    checked = toggles.verboseLog,
                    summary = "写入 DEBUG 级 XP 日志（默认仅关键事件）",
                    enabled = !busy,
                    onCheckedChange = { vm.setVerboseLog(it) },
                )
            }

            ChargeSection(title = "日志") {
                ChargeSecondaryButton(
                    text = "打开动态页 LSP 日志",
                    modifier = Modifier.fillMaxWidth(),
                    onClick = onOpenLspLog,
                )
            }

            Text(
                text = "当前作用域列表",
                style = ChargeTheme.typography.label,
                color = ChargeTheme.colors.accent,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = status?.scopeList?.joinToString("\n")?.ifBlank { "（空）" } ?: "—",
                style = ChargeTheme.typography.body,
                color = ChargeTheme.colors.ink,
            )
        }
    }
}
