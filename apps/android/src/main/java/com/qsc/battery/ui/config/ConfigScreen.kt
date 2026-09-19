package com.qsc.battery.ui.config

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.AppViewModelFactory
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargeEditSheet
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeSkeletonBox
import com.qsc.battery.ui.design.charge.ChargeStickyActionBar
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTopBar

@Composable
fun ConfigScreen(
    container: AppContainer,
    snackbar: SnackbarHostState,
    advancedOnly: Boolean = false,
    onOpenAdvanced: (() -> Unit)? = null,
    onBack: (() -> Unit)? = null,
) {
    val factory = remember(container) { AppViewModelFactory(container) }
    val vm: ConfigViewModel = viewModel(factory = factory)
    val ui by vm.ui.collectAsStateWithLifecycle()
    var edit by remember { mutableStateOf<ConfigEditField?>(null) }
    var editNight by remember { mutableStateOf(false) }

    fun v(key: String) = vm.v(key)
    fun setLocal(key: String, value: String) = vm.setLocal(key, value)

    LaunchedEffect(Unit) { vm.reload() }
    LaunchedEffect(ui.lastSaveMessage) {
        ui.lastSaveMessage?.let {
            snackbar.showSnackbar(it)
            vm.consumeSaveMessage()
        }
    }
    LaunchedEffect(ui.lastDaemonMessage) {
        ui.lastDaemonMessage?.let {
            snackbar.showSnackbar(it)
            vm.consumeDaemonMessage()
        }
    }

    val ready = ui.ready
    val rootOk = ui.rootOk
    val moduleOk = ui.moduleOk

    val notifyKinds = v("notify_charge_kinds")
        .split(',')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .toSet()
        .ifEmpty { setOf("stop", "resume", "fail") }

    val showSave = ready && rootOk && moduleOk

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(
            title = if (advancedOnly) "进阶策略" else "策略",
            subtitle = if (advancedOnly) null else "常用项一屏搞定，细节放进阶",
            onBack = onBack,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
                .padding(
                    top = ChargeTheme.dimens.pageContentTop,
                    bottom = ChargeTheme.dimens.bottomBarContentGap,
                ),
            verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
        ) {
            when {
                !ready -> {
                    ChargeSkeletonBox(height = 120.dp)
                    ChargeSkeletonBox(height = 80.dp)
                }

                !rootOk -> ChargeBanner("需要 Root 才能修改配置", BannerTone.Warn)

                !moduleOk -> ChargeBanner("模块未安装", BannerTone.Warn)

                !advancedOnly -> {
                    ConfigPowerSection(v = ::v, setLocal = ::setLocal, onEdit = { edit = it })
                    ConfigTempSection(v = ::v, setLocal = ::setLocal, onEdit = { edit = it })
                    ChargeSection(title = "更多") {
                        ChargeListRow(
                            title = "进阶策略",
                            summary = "循环间隔、电流控制、守护与通知",
                            onClick = { onOpenAdvanced?.invoke() },
                        )
                    }
                }

                else -> {
                    ConfigAdvancedSections(
                        vm = vm,
                        ui = ui,
                        v = ::v,
                        setLocal = ::setLocal,
                        notifyKinds = notifyKinds,
                        onEdit = { edit = it },
                        onEditNightSchedules = { editNight = true },
                    )
                }
            }
        }

        if (showSave) {
            ChargeStickyActionBar(clearSystemNav = advancedOnly) {
                ChargePrimaryButton(
                    text = if (advancedOnly) "保存进阶项" else "保存",
                    onClick = { vm.save(advancedOnly) },
                )
            }
        }
    }

    val field = edit
    if (field != null) {
        ChargeEditSheet(
            title = field.title,
            value = field.get(),
            unit = field.unit,
            numeric = field.numeric,
            step = field.step,
            onDismiss = { edit = null },
            onConfirm = {
                field.set(it)
                edit = null
            },
        )
    }

    if (editNight) {
        ChargeScheduleSheet(
            title = "夜间时段",
            ranges = ui.nightSchedules,
            onDismiss = { editNight = false },
            onSave = {
                vm.saveNightSchedules(it)
                editNight = false
            },
        )
    }
}
