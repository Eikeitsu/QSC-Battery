package com.qsc.battery.ui.more

import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTopBar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val CLEANUP_TAG = "QscUpdateCleanup"
private val ConsoleBg = Color(0xFF0D1117)
private val ConsoleFg = Color(0xFFC9D1D9)
private val ConsoleAccent = Color(0xFF3FB950)
private val ConsoleWarn = Color(0xFFD29922)
private val ConsoleErr = Color(0xFFF85149)

/**
 * 模块安装「命令行」页：展示下载与 magisk/ksud/apd 输出，非无感后台。
 */
@Composable
fun ModuleInstallConsoleScreen(
    container: AppContainer,
    zipUrl: String,
    onBack: () -> Unit,
    onFinished: () -> Unit = onBack,
) {
    val lines = remember { mutableStateListOf<String>() }
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var success by remember { mutableStateOf(false) }
    var progress by remember { mutableFloatStateOf(0f) }
    var started by remember { mutableStateOf(false) }

    fun log(line: String) {
        lines += line
    }

    suspend fun runInstall() {
        if (running) return
        running = true
        done = false
        success = false
        progress = 0f
        lines.clear()
        log("$ qsc module-install")
        log("# url=$zipUrl")
        try {
            val root = container.root
            if (!root.isRootAvailable()) {
                log("! no root — cannot run installers")
                done = true
                running = false
                return
            }
            log("$ downloading…")
            val file = container.updateRepository.downloadToCache(
                zipUrl,
                "QSC-Battery-update.zip",
            ) { read, total ->
                val f = if (total != null && total > 0L) {
                    (read.toDouble() / total.toDouble()).toFloat().coerceIn(0f, 1f)
                } else {
                    null
                }
                scope.launch(Dispatchers.Main.immediate) {
                    progress = f ?: progress
                    if (f != null && lines.lastOrNull()?.startsWith("# progress") == true) {
                        lines[lines.lastIndex] = "# progress ${(f * 100).toInt()}%"
                    } else if (f != null) {
                        log("# progress ${(f * 100).toInt()}%")
                    }
                }
            }
            progress = 1f
            log("# saved ${file.absolutePath} (${file.length()} bytes)")
            val localCode = container.statusRepository.readModuleProp()?.versionCode ?: 0L
            if (localCode in 1 until ModulePaths.LAYOUT_CUTOVER_CODE) {
                log("# layout cutover: local versionCode=$localCode < ${ModulePaths.LAYOUT_CUTOVER_CODE}")
                log("# will wipe conf/data (unattended still applies); reboot + reconfigure required")
            }
            log("# enabling unattended defaults (${ModulePaths.INSTALL_AUTO})")
            root.exec("mkdir -p /data/adb/qsc && touch '${ModulePaths.INSTALL_AUTO}'")
            val path = file.absolutePath.replace("'", "'\\''")
            val attempts = listOf(
                "magisk --install-module '$path'",
                "ksud module install '$path'",
                "/data/adb/ksud module install '$path'",
                "nsenter --mount=/proc/1/ns/mnt -- /data/adb/ksud module install '$path'",
                "nsenter --mount=/proc/1/ns/mnt -- /data/adb/magisk/magisk --install-module '$path'",
                "/data/adb/ap/bin/apd module install '$path'",
                "nsenter --mount=/proc/1/ns/mnt -- /data/adb/ap/bin/apd module install '$path'",
            )
            var installed = false
            try {
                for (cmd in attempts) {
                    log("$ $cmd")
                    val r = root.exec(cmd)
                    if (r.out.isNotBlank()) r.out.lineSequence().forEach { log(it) }
                    if (r.err.isNotBlank()) r.err.lineSequence().forEach { log("! $it") }
                    log("# exit=${r.code}")
                    if (r.ok) {
                        installed = true
                        log("# ok: installer accepted module")
                        break
                    }
                }
                if (!installed) {
                    log("# cli failed — opening zip for manager UI (keep install_auto for customize)")
                    withContext(Dispatchers.Main) {
                        container.moduleInstallRepository.promptOpenModuleZip(file)
                    }
                    log("# opened system chooser / manager")
                    success = true
                } else {
                    success = true
                }
            } finally {
                // CLI 成功 / 彻底失败：清 flag。打开管理器时保留，供稍后 customize 使用。
                if (installed || !success) {
                    root.exec(
                        "([ -f '${ModulePaths.INSTALL_AUTO}' ] && rm -f -- '${ModulePaths.INSTALL_AUTO}'); true " +
                            ">/dev/null 2>&1",
                    )
                }
                fun silentDeleteZip() {
                    if (!file.isFile) return
                    runCatching { file.delete() }
                    if (file.isFile) {
                        Log.d(CLEANUP_TAG, "cache still exists after delete: ${file.absolutePath}")
                    }
                }
                if (installed) {
                    silentDeleteZip()
                } else {
                    scope.launch(Dispatchers.IO) {
                        delay(180_000L)
                        silentDeleteZip()
                    }
                }
            }
        } catch (e: Exception) {
            log("! ${e.message ?: e::class.java.simpleName}")
            success = false
        }
        done = true
        running = false
        if (success) {
            container.updatesSession.refresh()
        }
    }

    LaunchedEffect(zipUrl) {
        if (!started && zipUrl.isNotBlank()) {
            started = true
            runInstall()
        }
    }

    LaunchedEffect(lines.size) {
        scroll.animateScrollTo(scroll.maxValue)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ChargeTopBar(title = "模块安装", onBack = onBack)
        if (running) {
            if (progress > 0f && progress < 1f) {
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(2.dp),
                    color = ChargeTheme.colors.accent,
                    trackColor = ChargeTheme.colors.stroke,
                )
            } else {
                LinearProgressIndicator(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(2.dp),
                    color = ChargeTheme.colors.accent,
                    trackColor = ChargeTheme.colors.stroke,
                )
            }
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
                .padding(top = 8.dp, bottom = ChargeTheme.dimens.sectionGap),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "下载后以命令行刷入；已启用无人值守默认（跳过音量键）。失败则打开管理器。",
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
            )
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(ConsoleBg)
                    .padding(12.dp),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(scroll),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    if (lines.isEmpty()) {
                        Text(
                            text = "等待开始…",
                            color = ConsoleFg.copy(alpha = 0.5f),
                            fontFamily = FontFamily.Monospace,
                            fontSize = 12.sp,
                        )
                    }
                    lines.forEach { line ->
                        val color = when {
                            line.startsWith("!") -> ConsoleErr
                            line.startsWith("# ok") || line.startsWith("# saved") -> ConsoleAccent
                            line.startsWith("#") -> ConsoleWarn
                            line.startsWith("$") -> ConsoleAccent
                            else -> ConsoleFg
                        }
                        Text(
                            text = line,
                            color = color,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 12.sp,
                            fontWeight = if (line.startsWith("$")) FontWeight.SemiBold else FontWeight.Normal,
                        )
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (done) {
                    ChargeSecondaryButton(
                        text = "重新执行",
                        modifier = Modifier.weight(1f),
                        enabled = !running,
                        onClick = {
                            scope.launch { runInstall() }
                        },
                    )
                    ChargePrimaryButton(
                        text = if (success) "完成" else "返回",
                        compact = true,
                        modifier = Modifier.weight(1f),
                        onClick = onFinished,
                    )
                } else {
                    ChargeSecondaryButton(
                        text = "取消返回",
                        enabled = !running,
                        onClick = onBack,
                    )
                }
            }
        }
    }
}
