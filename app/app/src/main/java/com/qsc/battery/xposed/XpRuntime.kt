package com.qsc.battery.xposed

import android.content.Context
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * XP / LSPosed 状态：
 * - 管理器 / 框架目录
 * - `modules_config.db`：是否启用、作用域是否含 `android`
 * - `/data/system/qsc_xp_alive`：system_server 存活标记（已进框架的强证据）
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

    private val SQLITE_BINS = listOf(
        "sqlite3",
        "/system/bin/sqlite3",
        "/system/xbin/sqlite3",
        "/data/adb/magisk/busybox",
    )

    private const val DB = "/data/adb/lspd/config/modules_config.db"
    private const val ALIVE = "/data/system/qsc_xp_alive"
    private const val ALIVE_MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000

    enum class Level {
        None,
        ManagerOnly,
        Framework,
        Enabled,
        Active,
    }

    data class Status(
        val level: Level,
        val managerInstalled: Boolean,
        val frameworkPresent: Boolean,
        val enabledInManager: Boolean,
        val scopedAndroid: Boolean,
        /** 作用域是否从 DB 可靠读到（false 时勿武断说「未勾选」） */
        val scopeKnown: Boolean,
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
        var scopeKnown = false

        if (hasRoot && root.exists(DB)) {
            val cfg = readLsposedConfig(root, ourPkgs)
            enabled = cfg.enabled
            scopedAndroid = cfg.scopedAndroid
            scopeKnown = cfg.scopeKnown
            if (!enabled) {
                // 无 sqlite 时的粗检：库里出现本包名
                val rough = root.exec(
                    "strings '$DB' 2>/dev/null | tr '\\0' '\\n' | grep -F 'com.qsc.battery' | head -n 8",
                )
                if (rough.ok && rough.out.contains("com.qsc.battery")) {
                    enabled = true
                }
            }
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

        // 存活标记只可能由 system_server 写出 → 作用域实际已含系统框架
        if (alive) {
            scopedAndroid = true
            scopeKnown = true
        }

        val level = when {
            alive -> Level.Active
            enabled -> Level.Enabled
            framework -> Level.Framework
            manager -> Level.ManagerOnly
            else -> Level.None
        }

        val detail = when (level) {
            Level.Active -> "XP 已在系统框架运行"
            Level.Enabled -> when {
                scopedAndroid -> "LSPosed 已启用本模块，作用域含系统框架；若功能异常请再重启一次"
                scopeKnown -> "LSPosed 已启用本模块，但作用域未含系统框架(android)，插拔唤醒不会生效"
                else -> "LSPosed 已启用本模块；未能从配置库确认作用域（设备可能无 sqlite3）。" +
                    "若已勾选系统框架可忽略本提示，重启后出现存活标记即可确认"
            }
            Level.Framework -> "已检测到 LSPosed，请启用「充电控制」并勾选系统框架后重启"
            Level.ManagerOnly -> "已安装 LSPosed 管理器"
            Level.None -> if (hasRoot) "未检测到 LSPosed" else "检测 XP 需 Root；或先安装 LSPosed"
        }

        Status(
            level = level,
            managerInstalled = manager,
            frameworkPresent = framework || (manager && !hasRoot),
            enabledInManager = enabled,
            scopedAndroid = scopedAndroid,
            scopeKnown = scopeKnown,
            frameworkAlive = alive,
            detail = detail,
        )
    }

    private data class LsposedCfg(
        val enabled: Boolean,
        val scopedAndroid: Boolean,
        val scopeKnown: Boolean,
    )

    private suspend fun readLsposedConfig(root: RootBridge, ourPkgs: List<String>): LsposedCfg {
        val pkgList = ourPkgs.joinToString(",") { "'$it'" }
        val sqlEnabled =
            "SELECT enabled FROM modules WHERE module_pkg_name IN ($pkgList) LIMIT 1;"
        // 兼容不同列名 / 是否 JOIN
        val sqlScopeVariants = listOf(
            "SELECT s.app_pkg_name FROM scope s JOIN modules m ON s.mid=m.mid " +
                "WHERE m.module_pkg_name IN ($pkgList) AND s.app_pkg_name='android' LIMIT 1;",
            "SELECT s.package_name FROM scope s JOIN modules m ON s.mid=m.mid " +
                "WHERE m.module_pkg_name IN ($pkgList) AND s.package_name='android' LIMIT 1;",
            "SELECT app_pkg_name FROM scope WHERE app_pkg_name='android' LIMIT 1;",
            "SELECT package_name FROM scope WHERE package_name='android' LIMIT 1;",
        )

        var enabled: Boolean? = null
        var scoped: Boolean? = null

        for (bin in SQLITE_BINS) {
            val prefix = when {
                bin.endsWith("busybox") -> "$bin sqlite3"
                else -> bin
            }
            // 探测是否可用
            val probe = root.exec("$prefix -version 2>/dev/null | head -n 1")
            if (!probe.ok && !probe.out.contains("SQLite", ignoreCase = true) &&
                bin != "sqlite3"
            ) {
                // sqlite3 无 version 时仍可能能跑 SELECT
                if (bin != "sqlite3") continue
            }

            if (enabled == null) {
                val en = root.exec("$prefix '$DB' \"$sqlEnabled\" 2>/dev/null")
                if (en.ok) {
                    val v = en.out.trim().lineSequence().firstOrNull()?.trim().orEmpty()
                    if (v.isNotEmpty()) {
                        enabled = v == "1" || v.equals("true", true)
                    }
                }
            }
            if (scoped == null) {
                for (sql in sqlScopeVariants) {
                    val sc = root.exec("$prefix '$DB' \"$sql\" 2>/dev/null")
                    if (!sc.ok) continue
                    val out = sc.out.trim()
                    if (out == "android" || out.lines().any { it.trim() == "android" }) {
                        scoped = true
                        break
                    }
                    // 查询成功但无 android 行
                    if (sc.err.isBlank() || sc.code == 0) {
                        // 若是带模块 JOIN 的查询且空结果，记为「已知无」；全局 scope 空则继续试
                        if (sql.contains("module_pkg_name")) {
                            scoped = false
                            break
                        }
                    }
                }
            }
            if (enabled != null && scoped != null) break
        }

        // 再退：从 dump 里找 android 与本模块 mid 的邻近关系太脆，只做「库中存在 android 作用域行」
        if (scoped == null) {
            val dump = root.exec(
                "strings '$DB' 2>/dev/null | tr '\\0' '\\n' | grep -x 'android' | head -n 1",
            )
            if (dump.ok && dump.out.trim() == "android") {
                // 只能说明库里有 android 字符串，不算确定勾选了本模块
                return LsposedCfg(
                    enabled = enabled == true,
                    scopedAndroid = false,
                    scopeKnown = enabled != null,
                )
            }
        }

        return LsposedCfg(
            enabled = enabled == true,
            scopedAndroid = scoped == true,
            scopeKnown = scoped != null,
        )
    }

    fun isAvailable(context: Context): Boolean = isManagerInstalled(context)
}
