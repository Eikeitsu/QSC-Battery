package com.qsc.battery.xposed

import android.content.Context
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** LSPosed / 框架侧状态探测（分层：管理器 / 框架 / 本模块心跳）。 */
object XpRuntime {
    const val HEARTBEAT_PATH = "/data/adb/qsc/xp_heartbeat"
    private const val HEARTBEAT_MAX_AGE_MS = 24L * 60L * 60L * 1000L

    private val MANAGER_PACKAGES = listOf(
        "org.lsposed.manager",
        "org.lsposed.manager.lpha",
        "io.github.lsposed.manager",
        "org.lsposed.manager.debug",
    )

    private val FRAMEWORK_PATHS = listOf(
        "/data/adb/lspd",
        "/data/adb/modules/zygisk_lsposed",
        "/data/adb/modules/LSPosed",
        "/data/adb/modules/riru_lsposed",
        "/data/adb/modules/zygisk_lsposed_debug",
    )

    private val MODULE_SCOPE_HINTS = listOf(
        "/data/adb/lspd/config",
        "/data/misc/lspd",
    )

    enum class Level { None, ManagerOnly, Framework, Injected }

    data class Status(
        val level: Level,
        val managerInstalled: Boolean,
        val frameworkPresent: Boolean,
        val injected: Boolean,
        val detail: String,
        val heartbeatAgeMs: Long? = null,
        val heartbeatReason: String? = null,
    )

    fun isManagerInstalled(context: Context): Boolean {
        val pm = context.packageManager
        return MANAGER_PACKAGES.any { pkg ->
            runCatching {
                pm.getPackageInfo(pkg, 0)
                true
            }.getOrDefault(false)
        }
    }

    /** 无 Root 时仅能看管理器；有 Root 时看框架目录 + 心跳。 */
    suspend fun probe(context: Context, root: RootBridge): Status = withContext(Dispatchers.IO) {
        val manager = isManagerInstalled(context)
        val hasRoot = root.isRootAvailable()
        val framework = if (hasRoot) {
            FRAMEWORK_PATHS.any { root.exists(it) }
        } else {
            false
        }
        val heartbeat = if (hasRoot) root.readFile(HEARTBEAT_PATH) else null
        val parsed = parseHeartbeat(heartbeat)
        val injected = parsed != null && parsed.ageMs in 0..HEARTBEAT_MAX_AGE_MS
        val scopeHint = if (hasRoot && framework && !injected) {
            MODULE_SCOPE_HINTS.any { root.exists(it) }
        } else {
            false
        }

        val level = when {
            injected -> Level.Injected
            framework -> Level.Framework
            manager -> Level.ManagerOnly
            else -> Level.None
        }

        val detail = when (level) {
            Level.Injected -> {
                val reason = parsed?.reason?.takeIf { it.isNotBlank() }?.let { "（$it）" }.orEmpty()
                "已注入系统并写入心跳$reason"
            }
            Level.Framework -> when {
                !hasRoot -> "已安装管理器；需 Root 才能确认框架与注入"
                heartbeat.isNullOrBlank() ->
                    "已检测到 LSPosed 框架，但尚无本模块心跳。请确认：作用域勾选系统框架(android) → 启用模块 → 重启手机（或强制停止系统框架）。"
                parsed == null ->
                    "已检测到框架，但心跳文件无法解析。可尝试重启后查看。"
                else ->
                    "已检测到框架，心跳已过期（约 ${parsed.ageMs / 3_600_000} 小时前）。模块可能未勾选 android 作用域，或重启后钩子未触发。请重新启用并重启。"
            }
            Level.ManagerOnly ->
                "已安装 LSPosed 管理器，请启用本模块并勾选系统框架(android) 后重启"
            Level.None -> if (hasRoot) {
                "未检测到 LSPosed 管理器或框架目录"
            } else {
                "未检测到 LSPosed 管理器（无 Root 时无法扫描框架目录）"
            }
        }.let { base ->
            if (scopeHint && level == Level.Framework) {
                "$base 已看到 lspd 配置目录，优先检查本模块是否对本机生效。"
            } else {
                base
            }
        }

        Status(
            level = level,
            managerInstalled = manager,
            frameworkPresent = framework || (manager && !hasRoot),
            injected = injected,
            detail = detail,
            heartbeatAgeMs = parsed?.ageMs,
            heartbeatReason = parsed?.reason,
        )
    }

    fun isAvailable(context: Context): Boolean = isManagerInstalled(context)

    private data class Heartbeat(val ageMs: Long, val reason: String?)

    private fun parseHeartbeat(raw: String?): Heartbeat? {
        if (raw.isNullOrBlank()) return null
        val first = raw.lineSequence().firstOrNull()?.trim() ?: return null
        val ts = first.substringBefore('\t').toLongOrNull() ?: return null
        val reason = first.substringAfter('\t', "").ifBlank { null }
        val age = System.currentTimeMillis() - ts
        return Heartbeat(ageMs = age, reason = reason)
    }
}
