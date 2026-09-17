package com.qsc.battery.ui.onboarding

import android.Manifest
import android.app.Activity
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.core.PermStatus
import com.qsc.battery.core.PermissionChecker
import com.qsc.battery.core.PermissionSnapshot
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.charge.BannerTone
import com.qsc.battery.ui.design.charge.ChargeBanner
import com.qsc.battery.ui.design.charge.ChargePage
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeScaffold
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.util.LifecycleResumeEffect
import com.qsc.battery.xposed.XpRuntime
import kotlinx.coroutines.launch

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
        snap = checker.snapshot(st.modulePresent, container.root)
        xp = XpRuntime.probe(context, container.root)
    }

    LifecycleResumeEffect { refresh() }

    val notifyLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { scope.launch { refresh() } }

    ChargeScaffold {
        ChargePage(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            Text(
                text = "充电控制",
                style = ChargeTheme.typography.title,
                color = ChargeTheme.colors.ink,
                fontWeight = FontWeight.Bold,
            )
            StepDots(total = 5, current = step)

            when (step) {
                0 -> {
                    Text(
                        text = "欢迎",
                        style = ChargeTheme.typography.headline,
                        color = ChargeTheme.colors.ink,
                    )
                    ChargeBanner(
                        text = "本应用用于配置与查看 Magisk「充电控制」模块，不在后台执行停充逻辑。\n\n" +
                            "接下来会检测权限。没有全部授权也能用主题与检查更新；停充配置需要 Root。\n\n" +
                            "LSPosed 为可选项：系统框架插拔边沿可在事件守护不可用时协助唤醒模块。",
                    )
                    ChargePrimaryButton("开始检测", onClick = { step = 1 })
                }

                1 -> {
                    Text(
                        text = "Root 权限",
                        style = ChargeTheme.typography.headline,
                        color = ChargeTheme.colors.ink,
                    )
                    ChargeBanner(
                        text = "为什么需要：读写模块配置、启停充电控制、查看实时电量与日志。\n" +
                            "拒绝会怎样：仍可改主题、检查更新；无法改停充策略或启停模块。",
                    )
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
                        ChargeSecondaryButton(
                            text = "重新检测",
                            equalHeight = true,
                            modifier = Modifier.weight(1f),
                            onClick = { scope.launch { refresh() } },
                        )
                        ChargePrimaryButton(
                            text = if (root == PermStatus.Ok) "下一步" else "暂时跳过",
                            modifier = Modifier.weight(1f),
                            onClick = { step = 2 },
                        )
                    }
                }

                2 -> {
                    Text(
                        text = "通知权限",
                        style = ChargeTheme.typography.headline,
                        color = ChargeTheme.colors.ink,
                    )
                    ChargeBanner(
                        text = "为什么需要：更新完成、模块安装结果等提示。\n" +
                            "拒绝会怎样：核心停充不受影响，只是少了系统通知提醒。",
                    )
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
                        ChargeSecondaryButton(
                            text = if (n == PermStatus.Ok) "已完成" else "去授权",
                            equalHeight = true,
                            modifier = Modifier.weight(1f),
                            onClick = {
                                if (Build.VERSION.SDK_INT >= 33) {
                                    notifyLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                } else {
                                    (context as? Activity)?.let { checker.requestNotifications(it) }
                                }
                            },
                        )
                        ChargePrimaryButton(
                            text = "下一步",
                            modifier = Modifier.weight(1f),
                            onClick = { step = 3 },
                        )
                    }
                }

                3 -> {
                    Text(
                        text = "安装应用权限",
                        style = ChargeTheme.typography.headline,
                        color = ChargeTheme.colors.ink,
                    )
                    ChargeBanner(
                        text = "为什么需要：在线下载并安装 / 更新本伴侣 APP。\n" +
                            "拒绝会怎样：无法一键更新 APP，仍可手动安装 APK。",
                    )
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
                        ChargeSecondaryButton(
                            text = if (i == PermStatus.Ok) "已完成" else "打开设置",
                            equalHeight = true,
                            modifier = Modifier.weight(1f),
                            onClick = { checker.openInstallPermissionSettings() },
                        )
                        ChargePrimaryButton(
                            text = "下一步",
                            modifier = Modifier.weight(1f),
                            onClick = { step = 4 },
                        )
                    }
                }

                else -> {
                    Text(
                        text = "可选 · LSPosed 增强",
                        style = ChargeTheme.typography.headline,
                        color = ChargeTheme.colors.ink,
                    )
                    ChargeBanner(
                        text = "为什么可选：事件守护不可用时，由系统框架在插拔边沿写唤醒标记，缩短 Magisk 轮询。\n" +
                            "不写充电节点。请启用本模块，作用域只勾选「系统框架」(system) 后重启。",
                    )
                    val status = xp
                    StatusBlock(
                        title = when (status?.level) {
                            XpRuntime.Level.Active -> "XP 已运行"
                            XpRuntime.Level.Enabled -> "XP 已启用"
                            XpRuntime.Level.Framework -> "框架已装未启用"
                            XpRuntime.Level.ManagerOnly -> "管理器已装"
                            else -> "未检测到 XP"
                        },
                        ok = status?.activated == true,
                        detail = status?.detail
                            ?: "安装 LSPosed 后启用本模块，作用域勾选系统框架 (system)",
                    )
                    ChargeBanner(
                        text = if (snap?.modulePresent == true) {
                            "Magisk 模块：已激活"
                        } else {
                            "Magisk 模块：未检测到，可稍后在「我的 → 更新」下载。"
                        },
                    )
                    ChargePrimaryButton(
                        text = "进入应用",
                        onClick = {
                            scope.launch {
                                container.settingsRepository.setOnboardingDone(true)
                                onFinished()
                            }
                        },
                    )
                    ChargeSecondaryButton(
                        text = "返回权限项",
                        equalHeight = true,
                        onClick = { step = 1 },
                    )
                }
            }
        }
    }
}

@Composable
private fun StepDots(total: Int, current: Int) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(vertical = 4.dp),
    ) {
        repeat(total) { i ->
            Box(
                modifier = Modifier
                    .size(if (i == current) 10.dp else 8.dp)
                    .clip(CircleShape)
                    .background(
                        if (i == current) {
                            ChargeTheme.colors.accent
                        } else {
                            ChargeTheme.colors.stroke
                        },
                    ),
            )
        }
    }
}

@Composable
private fun StatusBlock(title: String, ok: Boolean, detail: String) {
    ChargeBanner(
        text = "${if (ok) "✓" else "○"} $title\n$detail",
        tone = if (ok) BannerTone.Ok else BannerTone.Info,
    )
}
