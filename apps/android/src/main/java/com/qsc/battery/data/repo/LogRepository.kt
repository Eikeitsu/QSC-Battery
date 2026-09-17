package com.qsc.battery.data.repo

import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import com.qsc.battery.data.model.ChargeEvent
import com.qsc.battery.data.model.LogLine

class LogRepository(private val root: RootBridge) {
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
        // 空文件时给可读诊断，避免「成功了却像没日志」
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
}
