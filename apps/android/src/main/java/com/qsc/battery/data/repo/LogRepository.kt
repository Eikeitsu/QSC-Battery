package com.qsc.battery.data.repo

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import com.qsc.battery.data.model.ChargeEvent
import com.qsc.battery.data.model.LogLine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class LogRepository(
    private val context: Context,
    private val root: RootBridge,
) {
    private val eventRe =
        Regex("""^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+\[EVENT\]\s+([A-Z_]+)\s+(\d+|--)%\s+(\d+|--|-?\d+)°C\s*(.*)$""")

    suspend fun loadLogTail(maxLines: Int = 300): List<LogLine> {
        val r = root.exec("tail -n $maxLines '${ModulePaths.LOG_FILE}' 2>/dev/null")
        if (!r.ok || r.out.isBlank()) return emptyList()
        return r.out.lineSequence().map { line ->
            val level = when {
                line.contains("[ERROR]", true) || line.contains(" ERROR") -> "error"
                line.contains("[WARN]", true) || line.contains(" WARN") -> "warn"
                line.contains("[DEBUG]", true) || line.contains(" DEBUG") -> "debug"
                else -> "info"
            }
            LogLine(raw = line, level = level)
        }.toList()
    }

    suspend fun clearLog(): Boolean = root.exec(": > '${ModulePaths.LOG_FILE}' 2>/dev/null || rm -f '${ModulePaths.LOG_FILE}'").ok

    suspend fun loadEvents(maxLines: Int = 80): List<ChargeEvent> {
        val r = root.exec("tail -n $maxLines '${ModulePaths.CHARGE_EVENTS}' 2>/dev/null")
        if (!r.ok || r.out.isBlank()) return emptyList()
        return r.out.lineSequence().mapNotNull { line ->
            val m = eventRe.matchEntire(line) ?: return@mapNotNull null
            val (d, t, type, level, temp, detail) = m.destructured
            val ts = runCatching {
                java.time.LocalDateTime.parse("${d}T$t")
                    .atZone(java.time.ZoneId.systemDefault()).toEpochSecond()
            }.getOrDefault(0L)
            ChargeEvent(
                ts = ts,
                dateText = d,
                timeText = t,
                type = type,
                level = level.toIntOrNull(),
                temp = temp.toIntOrNull(),
                detail = detail,
                raw = line,
            )
        }.sortedByDescending { it.ts }.toList()
    }

    suspend fun clearEvents(): Boolean = root.exec(": > '${ModulePaths.CHARGE_EVENTS}' 2>/dev/null || rm -f '${ModulePaths.CHARGE_EVENTS}'").ok

    /**
     * 本模块 XP 文件日志：合并多候选路径（system / tmp / cache / 模块镜像）。
     * 打开页面时才 tail，不跑 logcat，无后台轮询。
     */
    suspend fun loadXpLog(maxLines: Int = 200): List<LogLine> {
        val paths = ModulePaths.XP_LOG_CANDIDATES.joinToString(" ") { "'$it'" }
        val r = root.exec(
            """
            {
              for f in $paths; do
                [ -f "${'$'}f" ] && cat "${'$'}f"
              done
            } 2>/dev/null | awk 'NF' | sort -n | uniq | tail -n $maxLines
            """.trimIndent(),
        )
        if (r.ok && r.out.isNotBlank()) {
            return r.out.lineSequence().map { parseXpLine(it) }.toList()
        }
        val probe = root.exec(
            """
            a=0; s=0; t=0; m=0; arm=0
            [ -f /data/system/qsc_xp_alive ] && a=1
            [ -f '${ModulePaths.XP_LOG}' ] && s=1
            [ -f '${ModulePaths.XP_LOG_TMP}' ] && t=1
            [ -f '${ModulePaths.XP_LOG_MODULE}' ] && m=1
            [ -f /data/system/qsc_xp_arm ] && arm=1
            printf 'alive=%s sys_log=%s tmp_log=%s mod_log=%s arm=%s' "${'$'}a" "${'$'}s" "${'$'}t" "${'$'}m" "${'$'}arm"
            """.trimIndent(),
        ).out.trim()
        val tip = if (probe.isBlank()) {
            "暂无 XP 写入。启用 LSPosed、勾选系统框架(system) 后重启；成功会出现 ok loaded / hooked / alive。"
        } else {
            "暂无 XP 文本行（$probe）。若 alive=1 仍无行，请再重启一次；武装边沿会写 ok wake。"
        }
        return listOf(LogLine(raw = tip, level = "warn"))
    }

    suspend fun clearXpLog(): Boolean {
        val rm = ModulePaths.XP_LOG_CANDIDATES.joinToString(" ") { "'$it'" }
        return root.exec("rm -f $rm 2>/dev/null; :").ok
    }

    private fun parseXpLine(line: String): LogLine {
        val parts = line.split('\t', limit = 3)
        val level = when {
            parts.size >= 2 -> when {
                parts[1].startsWith("ERR", ignoreCase = true) -> "error"
                parts[1].startsWith("WARN", ignoreCase = true) -> "warn"
                parts[1].startsWith("DEBUG", ignoreCase = true) -> "debug"
                else -> "info"
            }

            else -> "info"
        }
        val display = if (parts.size >= 3) {
            val ts = parts[0].toLongOrNull()
            val time = if (ts != null) {
                java.time.Instant.ofEpochMilli(ts)
                    .atZone(java.time.ZoneId.systemDefault())
                    .toLocalTime()
                    .toString()
                    .take(8)
            } else {
                parts[0]
            }
            "$time [${parts[1]}] ${parts[2]}"
        } else {
            line
        }
        return LogLine(raw = display, level = level)
    }

    suspend fun loadHistoryCsv(maxLines: Int = 500): String {
        val r = root.exec("tail -n $maxLines '${ModulePaths.CHARGE_HISTORY}' 2>/dev/null")
        return if (r.ok) r.out else ""
    }

    /**
     * 打包排障日志为 zip（运行日志 / 事件 / XP / 配置与标记），
     * 再经系统分享面板发出，方便微信等快捷反馈。
     */
    suspend fun exportLogsZip(): Result<File> = withContext(Dispatchers.IO) {
        if (!root.isRootAvailable()) {
            return@withContext Result.failure(IllegalStateException("需要 Root"))
        }
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val staging = File(context.cacheDir, "qsc_log_export").apply {
            deleteRecursively()
            mkdirs()
        }
        val stagingPath = staging.absolutePath.replace("'", "'\\''")
        val copyCmd = buildString {
            append("ST='$stagingPath'; mkdir -p \"\$ST\"; ")
            // 大文件只取尾部，避免 zip 过大难分享
            append("if [ -f '${ModulePaths.LOG_FILE}' ]; then ")
            append("tail -c 4194304 '${ModulePaths.LOG_FILE}' > \"\$ST/log.log\" 2>/dev/null || true; fi; ")
            append("if [ -f '${ModulePaths.CHARGE_EVENTS}' ]; then ")
            append("cp -f '${ModulePaths.CHARGE_EVENTS}' \"\$ST/charge_events.log\" 2>/dev/null || true; fi; ")
            append("if [ -f '${ModulePaths.CHARGE_HISTORY}' ]; then ")
            append("tail -n 800 '${ModulePaths.CHARGE_HISTORY}' > \"\$ST/charge_history.csv\" 2>/dev/null || true; fi; ")
            append("{ ")
            for (p in ModulePaths.XP_LOG_CANDIDATES) {
                append("[ -f '$p' ] && { echo '===== $p ====='; cat '$p'; echo; }; ")
            }
            append("} > \"\$ST/xp.log\" 2>/dev/null || true; ")
            append("[ -f '${ModulePaths.MODULE_PROP}' ] && cp -f '${ModulePaths.MODULE_PROP}' \"\$ST/module.prop\" || true; ")
            append("[ -f '${ModulePaths.CONF}' ] && cp -f '${ModulePaths.CONF}' \"\$ST/config.conf\" || true; ")
            append("[ -f '${ModulePaths.POWER_CONF}' ] && cp -f '${ModulePaths.POWER_CONF}' \"\$ST/power.conf\" || true; ")
            append("[ -f '${ModulePaths.NOTIFY_CONF}' ] && cp -f '${ModulePaths.NOTIFY_CONF}' \"\$ST/notify.conf\" || true; ")
            append("[ -f '${ModulePaths.CURRENT}' ] && cp -f '${ModulePaths.CURRENT}' \"\$ST/current.json\" || true; ")
            append("for f in service_start.log service_diag service_power_stats ")
            append("qscd_features qscd_unusable qscd_last_wake_reason resume_fail_hint ")
            append("power_switch active_switch debug_on hot_update_charge_dirty; do ")
            append("[ -e '${ModulePaths.DATADIR}/\$f' ] && cp -af '${ModulePaths.DATADIR}/\$f' \"\$ST/\$f\" 2>/dev/null || true; ")
            append("done; ")
            append("HU=/data/adb/qsc/runtime/diagnostics/hot_update.log; ")
            append("[ -f \"\$HU\" ] && cp -f \"\$HU\" \"\$ST/hot_update.log\" 2>/dev/null || true; ")
            append("DIAG=/sdcard/qsc_diagnose.txt; ")
            append("[ -f \"\$DIAG\" ] && cp -f \"\$DIAG\" \"\$ST/qsc_diagnose.txt\" 2>/dev/null || true; ")
            append("chmod -R a+r \"\$ST\" 2>/dev/null || true; true")
        }
        val copied = root.exec(copyCmd)
        if (!copied.ok && staging.listFiles().isNullOrEmpty()) {
            return@withContext Result.failure(
                IllegalStateException(copied.err.ifBlank { "收集日志失败" }),
            )
        }

        val meta = buildString {
            appendLine("QSC-Battery bugreport")
            appendLine("exported_at=$stamp")
            appendLine("app_version=${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            appendLine("app_id=${BuildConfig.APPLICATION_ID}")
            appendLine("module_id=${BuildConfig.MODULE_ID}")
            appendLine("---")
            appendLine(
                root.exec(
                    """
                    echo "model=$(getprop ro.product.model 2>/dev/null)"
                    echo "device=$(getprop ro.product.device 2>/dev/null)"
                    echo "fingerprint=$(getprop ro.build.fingerprint 2>/dev/null)"
                    echo "sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
                    echo "release=$(getprop ro.build.version.release 2>/dev/null)"
                    echo "magisk=$(magisk -v 2>/dev/null || true)"
                    [ -f '${ModulePaths.POWER_SWITCH_FLAG}' ] && echo power_switch=1 || echo power_switch=0
                    [ -f '${ModulePaths.DEBUG_ON}' ] && echo debug_on=1 || echo debug_on=0
                    [ -f '${ModulePaths.MODULE_OFF_FLAG}' ] && echo module_off=1 || echo module_off=0
                    [ -f /data/system/qsc_xp_alive ] && echo xp_alive=1 || echo xp_alive=0
                    """.trimIndent(),
                ).out.trim(),
            )
        }
        File(staging, "meta.txt").writeText(meta)

        val out = File(context.cacheDir, "QSC-Battery_logs_$stamp.zip")
        if (out.exists()) out.delete()
        ZipOutputStream(BufferedOutputStream(FileOutputStream(out))).use { zos ->
            staging.walkTopDown().filter { it.isFile }.forEach { file ->
                val entryName = file.relativeTo(staging).path.replace('\\', '/')
                zos.putNextEntry(ZipEntry(entryName))
                file.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }
        }
        staging.deleteRecursively()
        if (!out.exists() || out.length() == 0L) {
            return@withContext Result.failure(IllegalStateException("打包失败"))
        }
        Result.success(out)
    }

    fun shareExportedLogs(file: File) {
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, file.name)
            putExtra(
                Intent.EXTRA_TEXT,
                "QSC-Battery 排障日志 ${file.name}（含 log / 事件 / XP / 配置摘要）",
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, "导出日志").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
    }
}
