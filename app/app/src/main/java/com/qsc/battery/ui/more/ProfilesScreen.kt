package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeListRow
import com.qsc.battery.ui.design.charge.ChargePage
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeTitleBar
import kotlinx.coroutines.launch

@Composable
fun ProfilesScreen(
    container: AppContainer,
    onBack: () -> Unit,
    snackbar: SnackbarHostState,
) {
    var profiles by remember { mutableStateOf<List<String>>(emptyList()) }
    var profileName by remember { mutableStateOf("") }
    var bundleText by remember { mutableStateOf("") }
    var editingName by remember { mutableStateOf(false) }
    var editingBundle by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        profiles = container.profilesRepository.listNames()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        ChargeTitleBar(title = "配置档", onBack = onBack)
        ChargePage(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            includeStatusSpacer = false,
        ) {
            ChargeSection(title = "档位") {
                ChargeListRow(
                    title = "档位名称",
                    value = profileName.ifBlank { "点击填写" },
                    onClick = { editingName = true },
                )
                profiles.forEach { name ->
                    ChargeDivider()
                    ChargeListRow(
                        title = name,
                        summary = "点击应用此档位",
                        onClick = {
                            scope.launch {
                                val ok = container.profilesRepository.applyProfile(name, container.configRepository)
                                snackbar.showSnackbar(if (ok) "已应用 $name" else "应用失败")
                            }
                        },
                    )
                }
            }

            ChargePrimaryButton(
                text = "保存当前为档位",
                enabled = profileName.isNotBlank(),
                onClick = {
                    scope.launch {
                        val conf = container.configRepository.loadConf()
                        val current = container.root.readFile(ModulePaths.CURRENT)
                        val ok = container.profilesRepository.saveProfile(profileName.trim(), conf, current)
                        profiles = container.profilesRepository.listNames()
                        snackbar.showSnackbar(if (ok) "已保存档位" else "保存失败")
                    }
                },
            )

            ChargeSection(title = "导入 / 导出") {
                ChargeListRow(
                    title = "导出配置包",
                    summary = "生成可分享的 JSON",
                    onClick = {
                        scope.launch {
                            bundleText = container.profilesRepository.exportBundle().orEmpty()
                            snackbar.showSnackbar(
                                if (bundleText.isNotBlank()) "已导出 ${bundleText.length} 字符" else "导出失败",
                            )
                        }
                    },
                )
                ChargeDivider()
                ChargeListRow(
                    title = "编辑 / 粘贴 JSON",
                    summary = if (bundleText.isBlank()) "点击粘贴或编辑" else "已载入 ${bundleText.length} 字符",
                    onClick = { editingBundle = true },
                )
            }

            ChargeSecondaryButton(
                text = "导入配置包",
                onClick = {
                    scope.launch {
                        val ok = container.profilesRepository.importBundle(bundleText, container.configRepository)
                        snackbar.showSnackbar(if (ok) "导入成功" else "导入失败")
                    }
                },
            )
        }
    }

    if (editingName) {
        AlertDialog(
            onDismissRequest = { editingName = false },
            title = { Text("档位名称") },
            text = {
                OutlinedTextField(
                    value = profileName,
                    onValueChange = { profileName = it },
                    singleLine = true,
                    placeholder = { Text("例如：日常 / 出行") },
                )
            },
            confirmButton = {
                TextButton(onClick = { editingName = false }) { Text("确定") }
            },
            dismissButton = {
                TextButton(onClick = { editingName = false }) { Text("取消") }
            },
        )
    }
    if (editingBundle) {
        AlertDialog(
            onDismissRequest = { editingBundle = false },
            title = { Text("配置 JSON") },
            text = {
                OutlinedTextField(
                    value = bundleText,
                    onValueChange = { bundleText = it },
                    minLines = 6,
                    placeholder = { Text("粘贴导出的 JSON") },
                )
            },
            confirmButton = {
                TextButton(onClick = { editingBundle = false }) { Text("确定") }
            },
            dismissButton = {
                TextButton(onClick = { editingBundle = false }) { Text("取消") }
            },
        )
    }
}
