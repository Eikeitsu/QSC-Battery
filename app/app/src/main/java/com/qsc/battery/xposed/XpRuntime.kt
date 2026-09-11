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

    enum class Level { None, ManagerOnly, Framework, Injected }

    data class Status(
        val level: Level,
        val managerInstalled: Boolean,
        val frameworkPresent: Boolean,
        val injected: Boolean,
        val detail: String,
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
        val injected = heartbeatFresh(heartbeat)

        val level = when {
            injected -> Level.Injected
            framework || (manager && hasRoot && framework) -> Level.Framework
            framework -> Level.Framework
            manager -> Level.ManagerOnly
            else -> Level.None
        }.let {
            when {
                injected -> Level.Injected
                framework -> Level.Framework
                manager -> Level.ManagerOnly
                else -> Level.None
            }
        }

        val detail = when (level) {
            Level.Injected -> "已注入系统并写入心跳（运行中）"
            Level.Framework -> if (hasRoot) {
                "已检测到 LSPosed 框架，但本模块尚未注入或未重启"
            } else {
                "已安装管理器；需 Root 才能确认框架与注入"
            }
            Level.ManagerOnly -> "已安装 LSPosed 管理器，请启用本模块并勾选系统框架(android) 后重启"
            Level.None -> if (hasRoot) {
                "未检测到 LSPosed 管理器或框架目录"
            } else {
                "未检测到 LSPosed 管理器（无 Root 时无法扫描框架目录）"
            }
        }

        Status(
            level = level,
            managerInstalled = manager,
            frameworkPresent = framework || (manager && !hasRoot),
            injected = injected,
            detail = detail,
        )
    }

    fun isAvailable(context: Context): Boolean = isManagerInstalled(context)

    private fun heartbeatFresh(raw: String?): Boolean {
        if (raw.isNullOrBlank()) return false
        val ts = raw.lineSequence().firstOrNull()?.trim()?.substringBefore('\t')?.toLongOrNull()
            ?: return false
        return System.currentTimeMillis() - ts in 0..HEARTBEAT_MAX_AGE_MS
    }
}
