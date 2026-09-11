package com.qsc.battery.ui.onboarding

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.qsc.battery.core.PermStatus
import com.qsc.battery.core.PermissionChecker
import com.qsc.battery.core.PermissionSnapshot
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.components.PrefBody
import com.qsc.battery.ui.components.PrefCard
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun OnboardingScreen(
    container: AppContainer,
    onFinished: () -> Unit,
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val checker = remember { PermissionChecker(context) }
    val scope = rememberCoroutineScope()
    var step by remember { mutableIntStateOf(0) }
    var snap by remember { mutableStateOf<PermissionSnapshot?>(null) }

    suspend fun refresh() {
        val st = container.statusRepository.load()
        snap = checker.snapshot(st.modulePresent)
    }

    LaunchedEffect(step) {
        refresh()
        while (step == 1) {
            delay(1500)
            refresh()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("充电控制", style = MaterialTheme.typography.headlineMedium)
        LinearProgressIndicator(
            progress = { (step + 1) / 5f },
            modifier = Modifier.fillMaxWidth(),
        )

        when (step) {
            0 -> {
                Text("欢迎", style = MaterialTheme.typography.titleLarge)
                PrefCard {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("本应用用于配置与查看 Magisk「充电控制」模块，不在后台执行停充逻辑。")
                        Text("接下来会检测几项权限。Root 用于读写模块配置；没有 Root 仍可改主题、检查更新。")
                        Text("LSPosed 增强为可选项，用于系统侧供电事件补强，不写充电节点。")
                    }
                }
                Button(onClick = { step = 1 }, modifier = Modifier.fillMaxWidth()) { Text("开始检测") }
            }

            1 -> {
                Text("Root 权限", style = MaterialTheme.typography.titleLarge)
                val root = snap?.root
                StatusLine(
                    title = "Root",
                    ok = root == PermStatus.Ok,
                    detail = when (root) {
                        PermStatus.Ok -> "已获得"
                        else -> "未授权。请在 Magisk/KernelSU 中允许本应用，然后点「重新检测」"
                    },
                )
                PrefCard {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "为何需要：读写 /data/adb/modules 下的配置、安装模块、快捷磁贴切换。",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "可以跳过：仅使用主题与更新下载；停充相关功能会不可用。",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        onClick = { scope.launch { refresh() } },
                        modifier = Modifier.weight(1f),
                    ) { Text("重新检测") }
                    Button(onClick = { step = 2 }, modifier = Modifier.weight(1f)) {
                        Text(if (root == PermStatus.Ok) "下一步" else "暂时跳过")
                    }
                }
            }

            2 -> {
                Text("通知权限", style = MaterialTheme.typography.titleLarge)
                val n = snap?.notifications
                StatusLine(
                    title = "发送通知",
                    ok = n == PermStatus.Ok,
                    detail = if (n == PermStatus.Ok) "已授予" else "用于更新完成提示等（模块常显通知仍由模块发送）",
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        onClick = {
                            activity?.let { checker.requestNotifications(it) }
                            scope.launch {
                                delay(500)
                                refresh()
                            }
                        },
                        modifier = Modifier.weight(1f),
                    ) { Text("去授权") }
                    Button(onClick = { step = 3 }, modifier = Modifier.weight(1f)) { Text("下一步") }
                }
            }

            3 -> {
                Text("安装应用权限", style = MaterialTheme.typography.titleLarge)
                val i = snap?.installPackages
                StatusLine(
                    title = "安装未知应用",
                    ok = i == PermStatus.Ok,
                    detail = if (i == PermStatus.Ok) "已允许" else "用于安装/更新本 APP 的 APK",
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        onClick = {
                            checker.openInstallPermissionSettings()
                            scope.launch {
                                delay(800)
                                refresh()
                            }
                        },
                        modifier = Modifier.weight(1f),
                    ) { Text("打开设置") }
                    Button(onClick = { step = 4 }, modifier = Modifier.weight(1f)) { Text("下一步") }
                }
            }

            else -> {
                Text("可选 · LSPosed 增强", style = MaterialTheme.typography.titleLarge)
                val xp = snap?.xposedActive
                StatusLine(
                    title = "框架注入",
                    ok = xp == PermStatus.Ok,
                    detail = if (xp == PermStatus.Ok) {
                        "已检测到 LSPosed 管理器或框架目录；请在管理器中勾选「充电控制」，作用域为系统框架(android)，然后重启"
                    } else {
                        "未检测到 LSPosed。可安装后在管理器中启用本模块（API 102），作用域勾选系统框架"
                    },
                )
                PrefCard {
                    PrefBody(spacedBy = 6.dp) {
                        Text("增强内容：系统 BatteryService 变化时写入事件提示文件，帮助模块更快感知插拔。")
                        Text("不增强也不影响停充：模块本身已能工作。")
                        Text("使用现代 Xposed API 102，不写充电控制节点。")
                        Text(
                            if (snap?.modulePresent == true) "已检测到 Magisk 模块。"
                            else "尚未安装 Magisk 模块，可稍后在「更多 → 更新」下载。",
                        )
                    }
                }
                Button(
                    onClick = {
                        scope.launch {
                            container.settingsRepository.setOnboardingDone(true)
                            container.settingsRepository.setXpPowerEvents(true)
                            onFinished()
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("进入应用") }
                TextButton(onClick = { step = 1 }) { Text("返回权限项") }
            }
        }
    }
}

@Composable
private fun StatusLine(title: String, ok: Boolean, detail: String) {
    PrefCard {
        PrefBody(spacedBy = 4.dp) {
            Text(
                if (ok) "✓ $title" else "○ $title",
                style = MaterialTheme.typography.titleMedium,
                color = if (ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            )
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
