package com.qsc.battery.xposed

import android.content.Context
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * XP / LSPosed 状态（不自 hook）：
 * - 管理器 / 框架目录
 * - `modules_config.db` 是否启用本模块、作用域是否含 `android`
 * - `/data/system/qsc_xp_alive` 是否由 system_server 写出（实际已加载）
 */
object XpRuntime {
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
        "/data/adb/modules/lsposed",
    )

    private const val DB = "/data/adb/lspd/config/modules_config.db"
    private const val ALIVE = "/data/system/qsc_xp_alive"
    private const val ALIVE_MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000

    enum class Level {
        /** 未装管理器/框架 */
        None,
        /** 仅管理器 */
        ManagerOnly,
        /** 框架在，本模块未启用 */
        Framework,
        /** 管理器里已启用（或已含 android 作用域） */
        Enabled,
        /** system_server 已写出存活标记（真正跑起来） */
        Active,
    }

    data class Status(
        val level: Level,
        val managerInstalled: Boolean,
        val frameworkPresent: Boolean,
        /** LSPosed 配置中本模块 enabled */
        val enabledInManager: Boolean,
        /** 作用域含 android */
        val scopedAndroid: Boolean,
        /** 存活标记存在且未过期 */
        val frameworkAlive: Boolean,
        val detail: String,
    ) {
        val activated: Boolean get() = level == Level.Enabled || level == Level.Active
    }

    fun isManagerInstalled(context: Context): Boolean {
        val pm = context.packageManager
        return MANAGER_PACKAGES.any { pkg ->
            runCatching {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, 0)
                true
            }.getOrDefault(false)
        }
    }

    suspend fun probe(context: Context, root: RootBridge): Status = withContext(Dispatchers.IO) {
        val ourPkgs = listOf(BuildConfig.APPLICATION_ID, "com.qsc.battery", "com.qsc.battery.debug").distinct()
        val manager = isManagerInstalled(context)
        val hasRoot = root.isRootAvailable()
        val framework = if (hasRoot) FRAMEWORK_PATHS.any { root.exists(it) } else false

        var enabled = false
        var scopedAndroid = false
        if (hasRoot && root.exists(DB)) {
            val pkgList = ourPkgs.joinToString(",") { "'$it'" }
            val en = root.exec(
                "sqlite3 '$DB' \"SELECT enabled FROM modules WHERE module_pkg_name IN ($pkgList) LIMIT 1;\" 2>/dev/null",
            )
            if (en.ok) {
                val v = en.out.trim()
                enabled = v == "1" || v.equals("true", true)
            } else {
                // 无 sqlite3：退回 strings 粗检
                val rough = root.exec(
                    "strings '$DB' 2>/dev/null | tr '\\0' '\\n' | grep -E 'com\\.qsc\\.battery' | head -n 5",
                )
                enabled = rough.ok && rough.out.contains("com.qsc.battery")
            }
            val sc = root.exec(
                "sqlite3 '$DB' \"SELECT s.app_pkg_name FROM scope s " +
                    "JOIN modules m ON s.mid=m.mid " +
                    "WHERE m.module_pkg_name IN ($pkgList) AND s.app_pkg_name='android' LIMIT 1;\" 2>/dev/null",
            )
            scopedAndroid = sc.ok && sc.out.trim() == "android"
        }

        var alive = false
        if (hasRoot && root.exists(ALIVE)) {
            val raw = root.readFile(ALIVE)
            val ts = raw?.lineSequence()?.firstOrNull()?.substringBefore('\t')?.toLongOrNull()
            if (ts != null) {
                val age = System.currentTimeMillis() - ts
                alive = age in 0..ALIVE_MAX_AGE_MS
            } else {
                alive = true
            }
        }

        val level = when {
            alive -> Level.Active
            enabled && scopedAndroid -> Level.Enabled
            enabled -> Level.Enabled
            framework -> Level.Framework
            manager -> Level.ManagerOnly
            else -> Level.None
        }

        val detail = when (level) {
            Level.Active -> "XP 已在系统框架运行（存活标记）" +
                if (enabled) "" else "；管理器配置可读性有限"
            Level.Enabled -> if (scopedAndroid) {
                "LSPosed 已启用本模块且作用域含系统框架；若刚改过请重启"
            } else {
                "LSPosed 已启用本模块，但作用域未含「系统框架(android)」，插拔唤醒不会生效"
            }
            Level.Framework -> "已检测到 LSPosed，请启用「充电控制」模块并勾选系统框架后重启"
            Level.ManagerOnly -> "已安装 LSPosed 管理器"
            Level.None -> if (hasRoot) "未检测到 LSPosed" else "检测 XP 需 Root 读配置；或先安装 LSPosed"
        }

        Status(
            level = level,
            managerInstalled = manager,
            frameworkPresent = framework || (manager && !hasRoot),
            enabledInManager = enabled,
            scopedAndroid = scopedAndroid,
            frameworkAlive = alive,
            detail = detail,
        )
    }

    fun isAvailable(context: Context): Boolean = isManagerInstalled(context)
}
