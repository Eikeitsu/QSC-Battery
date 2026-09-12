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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.AppViewModelFactory
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import com.qsc.battery.ui.design.charge.ChargeTopBar
import com.qsc.battery.ui.util.LifecycleResumeEffect
import com.qsc.battery.xposed.XpPrefs

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

    val banner = when {
        status == null -> null
        status.frameworkAlive ->
            "③ 已注入 system_server。qscd 正常时「未武装」是预期；守护不可用时才会武装边沿唤醒。" to BannerTone.Ok
        status.scopeHintWrong ->
            "作用域请勾选 Android系统 (android)，不要勾「系统框架」(system)。改完后重启。" to BannerTone.Warn
        status.hasPrimaryScope && status.serviceBound ->
            "② 已含 android。请重启一次以完成③注入（出现存活标记）。" to BannerTone.Info
        status.serviceBound ->
            "① 服务已连接。请请求或勾选 Android系统 (android)，再重启。" to BannerTone.Warn
        else ->
            "请先在 LSPosed 启用本模块，再打开本页连接服务。" to BannerTone.Warn
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(
            title = "LSPosed / XP",
            subtitle = "边沿唤醒 · 不停充",
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
            banner?.let { (text, tone) -> ChargeBanner(text, tone) }

            ChargeSection(title = "进度") {
                ChargeListRow(
                    title = "① 服务",
                    summary = if (status?.serviceBound == true) {
                        listOfNotNull(
                            status.frameworkName,
                            status.frameworkVersion,
                            status.apiVersion?.let { "API $it" },
                        ).joinToString(" · ").ifBlank { "已连接" }
                    } else {
                        "未连接"
                    },
                    value = if (status?.serviceBound == true) "OK" else null,
                )
                ChargeDivider()
                ChargeListRow(
                    title = "② 作用域",
                    summary = when {
                        status?.hasPrimaryScope == true ->
                            "已含 ${XpPrefs.scopeLabel(XpPrefs.PRIMARY_SCOPE)}"
                        status?.scopeHintWrong == true ->
                            "仅有 system；应改为 android"
                        status?.scopeKnown == true ->
                            "未含 android"
                        else -> "未知"
                    },
                    value = when {
                        status?.hasPrimaryScope == true -> "OK"
                        status?.scopeKnown == true -> "缺"
                        else -> null
                    },
                )
                ChargeDivider()
                ChargeListRow(
                    title = "③ 注入",
                    summary = if (status?.frameworkAlive == true) {
                        "存活标记或运行目标已确认"
                    } else {
                        "勾选 android 后重启；看动态页 LSP 日志"
                    },
                    value = if (status?.frameworkAlive == true) "OK" else "待重启",
                )
            }

            ChargeSection(title = "作用域") {
                ChargeListRow(
                    title = "推荐",
                    summary = "LSPosed 里勾选「Android系统」，包名 android（注入 system_server）。" +
                        "「系统框架」包名 system 通常不是同一进程。",
                )
                ChargeDivider()
                val scopes = status?.scopeList.orEmpty()
                if (scopes.isEmpty()) {
                    ChargeListRow(title = "当前列表", summary = "（空）")
                } else {
                    scopes.forEachIndexed { index, pkg ->
                        if (index > 0) ChargeDivider()
                        val primary = pkg.trim().equals(XpPrefs.PRIMARY_SCOPE, ignoreCase = true)
                        ChargeListRow(
                            title = XpPrefs.scopeLabel(pkg),
                            summary = if (primary) "推荐 · 对应 system_server" else "一般不必勾选",
                            value = if (primary) "推荐" else null,
                        )
                    }
                }
                ChargeDivider()
                ChargeSecondaryButton(
                    text = if (busy) "请求中…" else "一键请求 Android系统 (android)",
                    enabled = !busy && status?.serviceBound == true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    onClick = { vm.requestSystemScope() },
                )
            }

            ChargeSection(title = "开关") {
                ChargeToggleRow(
                    title = "允许边沿唤醒",
                    checked = toggles.wakeEnabled && !toggles.xpOff,
                    summary = "仅在 qscd 不可用且已武装时写唤醒文件",
                    enabled = !busy,
                    onCheckedChange = { vm.setWakeEnabled(it) },
                )
                ChargeDivider()
                ChargeToggleRow(
                    title = "软关闭 XP",
                    checked = toggles.xpOff,
                    summary = "写入 qsc_xp_off；Magisk 与 XP 均尊重",
                    enabled = !busy,
                    onCheckedChange = { vm.setXpOff(it) },
                )
                ChargeDivider()
                ChargeToggleRow(
                    title = "详细日志",
                    checked = toggles.verboseLog,
                    summary = "DEBUG 级 XP 日志（默认仅关键事件）",
                    enabled = !busy,
                    onCheckedChange = { vm.setVerboseLog(it) },
                )
            }

            ChargeSection(title = "其它") {
                ChargeListRow(
                    title = "Magisk 武装",
                    summary = when {
                        status?.xpOffFile == true -> "软关闭中"
                        status?.armed == true -> "已武装（qscd 不可用时的边沿唤醒）"
                        else -> "未武装（qscd 正常时属预期，不代表 XP 未注入）"
                    },
                )
                ChargeDivider()
                ChargeListRow(
                    title = "运行目标",
                    summary = status?.runningTargets
                        ?.joinToString()
                        ?.ifBlank { "无（注入后可见 system_server）" }
                        ?: "—",
                )
                ChargeDivider()
                ChargeListRow(
                    title = "LSP 日志",
                    summary = "动态页 · 本模块 XP 日志",
                    onClick = onOpenLspLog,
                )
            }

            Text(
                text = status?.detail ?: "",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }
    }
}
