package com.qsc.battery.ui.onboarding

import android.Manifest
import android.app.Activity
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.moriafly.salt.ui.RoundedColumn
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text
import com.moriafly.salt.ui.UnstableSaltUiApi
import com.qsc.battery.core.PermStatus
import com.qsc.battery.core.PermissionChecker
import com.qsc.battery.core.PermissionSnapshot
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.AppChrome
import com.qsc.battery.ui.design.AppPage
import com.qsc.battery.ui.design.AppPrimaryButton
import com.qsc.battery.ui.design.AppSecondaryButton
import com.qsc.battery.ui.design.VoltBanner
import com.qsc.battery.xposed.XpRuntime
import kotlinx.coroutines.launch

@OptIn(UnstableSaltUiApi::class)
@Composable
fun OnboardingScreen(
    container: AppContainer,
    onFinished: () -> Unit,
) {
    val context = LocalContext.current
    val checker = remember { PermissionChecker(context) }
    val scope = rememberCoroutineScope()
    var step by remember { mutableIntStateOf(0) }
    var snap by remember { mutableStateOf<PermissionSnapshot?>(null) }
    var xp by remember { mutableStateOf<XpRuntime.Status?>(null) }

    suspend fun refresh() {
        val st = container.statusRepository.load()
        snap = checker.snapshot(st.modulePresent)
        xp = XpRuntime.probe(context, container.root)
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                scope.launch { refresh() }
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    val notifyLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { scope.launch { refresh() } }

    AppChrome {
        AppPage(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            Text(
                text = "充电控制",
                style = SaltTheme.textStyles.main,
                fontWeight = FontWeight.Bold,
            )
            LinearProgressIndicator(
                progress = { (step + 1) / 5f },
                modifier = Modifier.fillMaxWidth(),
                color = SaltTheme.colors.highlight,
                trackColor = SaltTheme.colors.stroke,
            )

            when (step) {
                0 -> {
                    Text(text = "欢迎", style = SaltTheme.textStyles.main, fontWeight = FontWeight.SemiBold)
                    RoundedColumn {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(text = "本应用用于配置与查看 Magisk「充电控制」模块，不在后台执行停充逻辑。")
                            Text(
                                text = "接下来会检测权限。Root 用于读写模块配置；没有 Root 仍可改主题、检查更新。",
                                color = SaltTheme.colors.subText,
                                style = SaltTheme.textStyles.sub,
                            )
                            Text(
                                text = "LSPosed 增强为可选项，不写充电节点。",
                                color = SaltTheme.colors.subText,
                                style = SaltTheme.textStyles.sub,
                            )
                        }
                    }
                    AppPrimaryButton("开始检测", onClick = { step = 1 })
                }

                1 -> {
                    Text(text = "Root 权限", style = SaltTheme.textStyles.main, fontWeight = FontWeight.SemiBold)
                    val root = snap?.root
                    StatusBlock(
                        title = "Root",
                        ok = root == PermStatus.Ok,
                        detail = when (root) {
                            PermStatus.Ok -> "已获得"
                            else -> "未授权。请在 Magisk/KernelSU 中允许本应用，然后点「重新检测」"
                        },
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        AppSecondaryButton(
                            text = "重新检测",
                            onClick = { scope.launch { refresh() } },
                            modifier = Modifier.weight(1f),
                        )
                        AppPrimaryButton(
                            text = if (root == PermStatus.Ok) "下一步" else "暂时跳过",
                            onClick = { step = 2 },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }

                2 -> {
                    Text(text = "通知权限", style = SaltTheme.textStyles.main, fontWeight = FontWeight.SemiBold)
                    val n = snap?.notifications
                    StatusBlock(
                        title = "发送通知",
                        ok = n == PermStatus.Ok,
                        detail = if (n == PermStatus.Ok) "已授予" else "用于更新完成提示等",
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        AppSecondaryButton(
                            text = if (n == PermStatus.Ok) "已完成" else "去授权",
                            onClick = {
                                if (Build.VERSION.SDK_INT >= 33) {
                                    notifyLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                } else {
                                    (context as? Activity)?.let { checker.requestNotifications(it) }
                                }
                            },
                            modifier = Modifier.weight(1f),
                        )
                        AppPrimaryButton(
                            text = "下一步",
                            onClick = { step = 3 },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }

                3 -> {
                    Text(text = "安装应用权限", style = SaltTheme.textStyles.main, fontWeight = FontWeight.SemiBold)
                    val i = snap?.installPackages
                    StatusBlock(
                        title = "安装未知应用",
                        ok = i == PermStatus.Ok,
                        detail = if (i == PermStatus.Ok) "已允许" else "用于安装/更新本 APP 的 APK",
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        AppSecondaryButton(
                            text = if (i == PermStatus.Ok) "已完成" else "打开设置",
                            onClick = { checker.openInstallPermissionSettings() },
                            modifier = Modifier.weight(1f),
                        )
                        AppPrimaryButton(
                            text = "下一步",
                            onClick = { step = 4 },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }

                else -> {
                    Text(
                        text = "可选 · LSPosed 增强",
                        style = SaltTheme.textStyles.main,
                        fontWeight = FontWeight.SemiBold,
                    )
                    val status = xp
                    StatusBlock(
                        title = when (status?.level) {
                            XpRuntime.Level.Injected -> "已注入运行"
                            XpRuntime.Level.Framework -> "框架已装"
                            XpRuntime.Level.ManagerOnly -> "管理器已装"
                            else -> "未检测到"
                        },
                        ok = status?.level == XpRuntime.Level.Injected || status?.level == XpRuntime.Level.Framework,
                        detail = status?.detail
                            ?: "可安装 LSPosed 后启用本模块（API 102），作用域勾选系统框架",
                    )
                    RoundedColumn {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text(text = "增强：系统 BatteryService 变化时写事件提示，帮助模块更快感知插拔。")
                            Text(
                                text = "不增强也不影响停充。",
                                color = SaltTheme.colors.subText,
                                style = SaltTheme.textStyles.sub,
                            )
                            Text(
                                text = if (snap?.modulePresent == true) {
                                    "已检测到 Magisk 模块。"
                                } else {
                                    "尚未安装 Magisk 模块，可稍后在「我的 → 更新」下载。"
                                },
                                color = SaltTheme.colors.subText,
                                style = SaltTheme.textStyles.sub,
                            )
                        }
                    }
                    AppPrimaryButton(
                        text = "进入应用",
                        onClick = {
                            scope.launch {
                                container.settingsRepository.setOnboardingDone(true)
                                container.settingsRepository.setXpPowerEvents(true)
                                onFinished()
                            }
                        },
                    )
                    AppSecondaryButton(text = "返回权限项", onClick = { step = 1 })
                }
            }
        }
    }
}

@Composable
private fun StatusBlock(title: String, ok: Boolean, detail: String) {
    if (ok) {
        VoltBanner("✓ $title\n$detail", accent = SaltTheme.colors.highlight)
    } else {
        VoltBanner("○ $title\n$detail")
    }
}
