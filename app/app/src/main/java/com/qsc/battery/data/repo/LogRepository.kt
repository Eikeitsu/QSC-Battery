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

    suspend fun clearLog(): Boolean =
        root.exec(": > '${ModulePaths.LOG_FILE}' 2>/dev/null || rm -f '${ModulePaths.LOG_FILE}'").ok

    suspend fun loadEvents(maxLines: Int = 80): List<ChargeEvent> {
        val r = root.exec("tail -n $maxLines '${ModulePaths.CHARGE_EVENTS}' 2>/dev/null")
        if (!r.ok || r.out.isBlank()) return emptyList()
        return r.out.lineSequence().mapNotNull { line ->
            val m = eventRe.matchEntire(line) ?: return@mapNotNull null
            val (d, t, type, level, temp, detail) = m.destructured
            val ts = runCatching {
                java.time.LocalDateTime.parse("${d}T${t}")
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

    suspend fun clearEvents(): Boolean =
        root.exec(": > '${ModulePaths.CHARGE_EVENTS}' 2>/dev/null || rm -f '${ModulePaths.CHARGE_EVENTS}'").ok

    /**
     * 仅本模块 XP 文件日志（/data/system/qsc_xp.log）。
     * 打开页面时才 tail，不跑 logcat，无后台轮询。
     */
    suspend fun loadXpLog(maxLines: Int = 200): List<LogLine> {
        val r = root.exec("tail -n $maxLines '${ModulePaths.XP_LOG}' 2>/dev/null")
        if (!r.ok || r.out.isBlank()) return emptyList()
        return r.out.lineSequence().map { parseXpLine(it) }.toList()
    }

    suspend fun clearXpLog(): Boolean =
        root.exec(": > '${ModulePaths.XP_LOG}' 2>/dev/null || rm -f '${ModulePaths.XP_LOG}'").ok

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
