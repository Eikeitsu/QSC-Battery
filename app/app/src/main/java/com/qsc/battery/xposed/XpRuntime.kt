package com.qsc.battery.xposed

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * XP / LSPosed 状态：
 * - 管理器 / 框架目录
 * - `modules_config.db`：Root 拷贝后用系统 [SQLiteDatabase] 读（不依赖手机是否有 sqlite3 命令）
 * - 系统框架在库中常记为 `system`（LSPosed 会把 `android` 迁成 `system`）
 * - `/data/system/qsc_xp_alive`：system_server 存活标记
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

    /** LSPosed 配置库中「系统框架」可能是 android 或 system */
    private val SYSTEM_SCOPE_PKGS = setOf("android", "system")

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
            val cfg = readLsposedConfig(context, root, ourPkgs)
            enabled = cfg.enabled
            scopedAndroid = cfg.scopedAndroid
            scopeKnown = cfg.scopeKnown
            if (!enabled) {
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
                scopedAndroid -> "LSPosed 已启用本模块，作用域含系统框架；未见存活标记，请确认已重启或查看 LSP 日志"
                scopeKnown -> "LSPosed 已启用本模块，但作用域未含系统框架（库中为 system/android），插拔唤醒不会生效"
                else -> "LSPosed 已启用本模块；配置库暂无法解析作用域。请在管理器确认勾选系统框架后重启"
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

    /**
     * 不依赖设备上的 sqlite3 CLI（多数 ROM 没有）。
     * Root 把 DB（及 wal/shm）拷到 APP 缓存，再用系统 SQLite 只读打开。
     */
    private suspend fun readLsposedConfig(
        context: Context,
        root: RootBridge,
        ourPkgs: List<String>,
    ): LsposedCfg {
        val dir = File(context.cacheDir, "lsp_probe").apply { mkdirs() }
        val local = File(dir, "modules_config.db")
        val localWal = File(dir, "modules_config.db-wal")
        val localShm = File(dir, "modules_config.db-shm")
        runCatching { local.delete() }
        runCatching { localWal.delete() }
        runCatching { localShm.delete() }

        val copy = root.exec(
            """
            cp -f '$DB' '${local.absolutePath}' 2>/dev/null
            [ -f '$DB-wal' ] && cp -f '$DB-wal' '${localWal.absolutePath}' 2>/dev/null
            [ -f '$DB-shm' ] && cp -f '$DB-shm' '${localShm.absolutePath}' 2>/dev/null
            chmod 666 '${local.absolutePath}' '${localWal.absolutePath}' '${localShm.absolutePath}' 2>/dev/null
            [ -f '${local.absolutePath}' ] && echo OK || echo FAIL
            """.trimIndent(),
        )
        if (!copy.out.contains("OK") || !local.isFile) {
            return readLsposedConfigViaCliFallback(root, ourPkgs)
        }

        return try {
            SQLiteDatabase.openDatabase(
                local.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            ).use { db ->
                parseLsposedDb(db, ourPkgs)
            }
        } catch (_: Throwable) {
            readLsposedConfigViaCliFallback(root, ourPkgs)
        } finally {
            runCatching { local.delete() }
            runCatching { localWal.delete() }
            runCatching { localShm.delete() }
        }
    }

    private fun parseLsposedDb(db: SQLiteDatabase, ourPkgs: List<String>): LsposedCfg {
        var enabled: Boolean? = null
        var mid: Long? = null

        val placeholders = ourPkgs.joinToString(",") { "?" }
        runCatching {
            db.rawQuery(
                "SELECT mid, enabled FROM modules WHERE module_pkg_name IN ($placeholders) LIMIT 1",
                ourPkgs.toTypedArray(),
            ).use { c ->
                if (c.moveToFirst()) {
                    mid = c.getLong(0)
                    enabled = c.getInt(1) == 1
                }
            }
        }

        var scoped: Boolean? = null
        if (mid != null) {
            runCatching {
                db.rawQuery(
                    "SELECT app_pkg_name FROM scope WHERE mid=? LIMIT 32",
                    arrayOf(mid.toString()),
                ).use { c ->
                    scoped = false
                    while (c.moveToNext()) {
                        val pkg = c.getString(0)?.trim().orEmpty()
                        if (pkg in SYSTEM_SCOPE_PKGS) {
                            scoped = true
                            break
                        }
                    }
                }
            }
            // 旧列名兼容
            if (scoped == null) {
                runCatching {
                    db.rawQuery(
                        "SELECT package_name FROM scope WHERE mid=? LIMIT 32",
                        arrayOf(mid.toString()),
                    ).use { c ->
                        scoped = false
                        while (c.moveToNext()) {
                            val pkg = c.getString(0)?.trim().orEmpty()
                            if (pkg in SYSTEM_SCOPE_PKGS) {
                                scoped = true
                                break
                            }
                        }
                    }
                }
            }
        }

        return LsposedCfg(
            enabled = enabled == true,
            scopedAndroid = scoped == true,
            scopeKnown = mid != null && scoped != null,
        )
    }

    /** 仅作兜底：少数环境若拷贝失败，再试 PATH 里的 sqlite3（多数机没有） */
    private suspend fun readLsposedConfigViaCliFallback(
        root: RootBridge,
        ourPkgs: List<String>,
    ): LsposedCfg {
        val pkgList = ourPkgs.joinToString(",") { "'$it'" }
        val bins = listOf(
            "sqlite3",
            "/system/bin/sqlite3",
            "/data/adb/magisk/busybox sqlite3",
        )
        for (bin in bins) {
            val en = root.exec(
                "$bin '$DB' \"SELECT enabled FROM modules WHERE module_pkg_name IN ($pkgList) LIMIT 1;\" 2>/dev/null",
            )
            if (!en.ok || en.out.isBlank()) continue
            val enabled = en.out.trim().lineSequence().firstOrNull()?.trim().let {
                it == "1" || it.equals("true", true)
            }
            val sc = root.exec(
                "$bin '$DB' \"SELECT s.app_pkg_name FROM scope s JOIN modules m ON s.mid=m.mid " +
                    "WHERE m.module_pkg_name IN ($pkgList) LIMIT 32;\" 2>/dev/null",
            )
            if (!sc.ok) {
                return LsposedCfg(enabled = enabled, scopedAndroid = false, scopeKnown = false)
            }
            val pkgs = sc.out.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toSet()
            return LsposedCfg(
                enabled = enabled,
                scopedAndroid = pkgs.any { it in SYSTEM_SCOPE_PKGS },
                scopeKnown = true,
            )
        }
        return LsposedCfg(enabled = false, scopedAndroid = false, scopeKnown = false)
    }

    fun isAvailable(context: Context): Boolean = isManagerInstalled(context)
}
