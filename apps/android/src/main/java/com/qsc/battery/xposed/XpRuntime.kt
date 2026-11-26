package com.qsc.battery.xposed

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import com.qsc.battery.BuildConfig
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * XP / LSPosed 三层状态：
 * 1. 服务已连接（XposedService binder）— 打开 APP 即可，不必重启
 * 2. 作用域已含 system（虚拟包 · system_server）— getScope / 一键 requestScope
 * 3. 框架已注入 — qsc_xp_alive 或 runningTargets 含 system_server
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
    /** 与 Magisk QSC_XP_ALIVE_MAX_AGE_SEC（48h）对齐；面板用此判「新鲜」 */
    private const val ALIVE_MAX_AGE_MS = 48L * 60 * 60 * 1000

    enum class Level {
        None,
        ManagerOnly,
        Framework,
        Enabled,
        Active,
    }

    data class BusFileSnap(
        val label: String,
        val path: String,
        val present: Boolean,
        val ageSec: Long?,
        val preview: String,
    )

    data class Status(
        val level: Level,
        val managerInstalled: Boolean,
        val frameworkPresent: Boolean,
        val enabledInManager: Boolean,
        val scopedAndroid: Boolean,
        val scopeKnown: Boolean,
        val frameworkAlive: Boolean,
        val serviceBound: Boolean,
        val scopeList: List<String>,
        /** 已勾选推荐的 system（system_server） */
        val hasPrimaryScope: Boolean,
        /** 仅有 android、没有 system 时的误勾提示 */
        val scopeHintWrong: Boolean,
        val runningTargets: List<String>,
        val frameworkName: String?,
        val frameworkVersion: String?,
        val apiVersion: Int?,
        val armed: Boolean,
        val xpOffFile: Boolean,
        val detail: String,
        /** alive 行内 v=；旧文件可能为 null */
        val aliveBusVer: Int? = null,
        val busSnapshot: List<BusFileSnap> = emptyList(),
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

        val svc = XpServiceHolder.awaitService(2000L)
        var enabled = false
        var scopedAndroid = false
        var scopeKnown = false
        var viaService = false
        var scopeList = emptyList<String>()
        var running = emptyList<String>()
        var fwName: String? = null
        var fwVer: String? = null
        var api: Int? = null

        if (svc != null) {
            viaService = true
            enabled = true
            val info = XpServiceHolder.frameworkInfo(svc)
            fwName = info?.name
            fwVer = info?.version
            api = info?.apiVersion
            scopeList = XpServiceHolder.scopeList(svc)
            scopeKnown = true
            scopedAndroid = XpPrefs.hasAnyFrameworkScope(scopeList)
            running = XpServiceHolder.runningTargetNames(svc)
        } else if (hasRoot && root.exists(DB)) {
            val cfg = readLsposedConfigDb(context, root, ourPkgs)
            enabled = cfg.enabled
            scopedAndroid = cfg.scopedAndroid
            scopeKnown = cfg.scopeKnown
            if (!enabled) {
                val rough = root.exec(
                    "strings '$DB' 2>/dev/null | tr '\\0' '\\n' | grep -F 'com.qsc.battery' | head -n 8",
                )
                if (rough.ok && rough.out.contains("com.qsc.battery")) enabled = true
            }
        }

        var alive = false
        var aliveBusVer: Int? = null
        if (hasRoot) {
            for (path in XpPrefs.ALIVE_CANDIDATES) {
                if (!root.exists(path)) continue
                val raw = root.readFile(path) ?: continue
                if (!raw.contains("alive")) continue
                val first = raw.lineSequence().firstOrNull().orEmpty()
                val ts = first.substringBefore('\t').toLongOrNull()
                val ver = Regex("""v=(\d+)""").find(first)?.groupValues?.getOrNull(1)?.toIntOrNull()
                alive = if (ts != null) {
                    val age = System.currentTimeMillis() - ts
                    age in 0..ALIVE_MAX_AGE_MS
                } else {
                    // 无毫秒戳：交给总线快照 mtime；此处先认存在
                    true
                }
                if (alive) {
                    aliveBusVer = ver
                    break
                }
            }
        }
        // 文件写失败时仍可凭日志判定已注入（loaded / hooked / alive 行）
        if (!alive && hasRoot) {
            alive = probeAliveFromXpLog(root)
        }
        val busSnapshot = if (hasRoot) probeBusSnapshot(root) else emptyList()
        // mtime 过期时纠正 alive（与 Magisk 48h 一致）
        if (alive && aliveBusVer == null) {
            val aliveSnap = busSnapshot.firstOrNull { it.label == "alive" }
            val age = aliveSnap?.ageSec
            if (age != null && age > ALIVE_MAX_AGE_MS / 1000) {
                alive = false
            }
        }
        val targetInjected = running.any {
            val n = it.lowercase()
            n == "system_server" || n == "system" || n.endsWith("/system_server")
        }
        if (alive || targetInjected) {
            scopedAndroid = true
            scopeKnown = true
        }

        val armed = hasRoot && root.exists(XpPrefs.ARM_PATH)
        val xpOff = hasRoot && root.exists(XpPrefs.OFF_PATH)
        val hasPrimary = XpPrefs.hasPrimaryScope(scopeList) || alive || targetInjected
        val wrongScope = scopeKnown &&
            scopeList.any { it.trim().equals("android", ignoreCase = true) } &&
            !XpPrefs.hasPrimaryScope(scopeList) &&
            !alive &&
            !targetInjected

        val level = when {
            alive || targetInjected -> Level.Active
            enabled || viaService -> Level.Enabled
            framework -> Level.Framework
            manager -> Level.ManagerOnly
            else -> Level.None
        }

        val fwHint = listOfNotNull(fwName, fwVer).joinToString(" ").takeIf { it.isNotBlank() }
            ?.let { "（$it）" }.orEmpty()
        val verHint = aliveBusVer?.let { " · 总线 v=$it" }.orEmpty()
        val detail = when (level) {
            Level.Active -> "③ 框架已注入$fwHint$verHint"

            Level.Enabled -> when {
                wrongScope ->
                    "② 仅勾了 android；注入 system_server 需勾「系统框架」包名 system 后重启"

                hasPrimary && viaService ->
                    "② 服务已连接且作用域含 system$fwHint；重启后出现存活标记即③完成"

                hasPrimary ->
                    "作用域已含 system；打开 APP 建立服务连接，重启后完成注入"

                scopedAndroid && viaService ->
                    "① 服务已连接$fwHint；作用域需含系统框架 (system)"

                scopeKnown && viaService ->
                    "① 服务已连接$fwHint，请勾选/请求系统框架 (system)"

                viaService ->
                    "① 服务已连接$fwHint"

                else ->
                    "模块已启用；打开本 APP 以连接 LSPosed 服务"
            }

            Level.Framework ->
                "已检测到 LSPosed，请启用本模块并勾选系统框架 (system)；读作用域不必重启，注入需重启"

            Level.ManagerOnly -> "已安装 LSPosed 管理器"

            Level.None -> if (hasRoot) "未检测到 LSPosed" else "检测 XP 需 Root；或先安装 LSPosed"
        }

        Status(
            level = level,
            managerInstalled = manager,
            frameworkPresent = framework || viaService || (manager && !hasRoot),
            enabledInManager = enabled || viaService,
            scopedAndroid = scopedAndroid || hasPrimary,
            scopeKnown = scopeKnown,
            frameworkAlive = alive || targetInjected,
            serviceBound = viaService,
            scopeList = scopeList,
            hasPrimaryScope = hasPrimary,
            scopeHintWrong = wrongScope,
            runningTargets = running,
            frameworkName = fwName,
            frameworkVersion = fwVer,
            apiVersion = api,
            armed = armed,
            xpOffFile = xpOff,
            detail = detail,
            aliveBusVer = aliveBusVer,
            busSnapshot = busSnapshot,
        )
    }

    private suspend fun probeBusSnapshot(root: RootBridge): List<BusFileSnap> {
        val specs = listOf(
            "alive" to XpPrefs.ALIVE_PATH,
            "plug" to XpPrefs.PLUG_PATH,
            "screen" to XpPrefs.SCREEN_PATH,
            "doze" to XpPrefs.DOZE_PATH,
            "fg" to XpPrefs.FG_PATH,
            "viewer" to XpPrefs.VIEWER_PATH,
            "wake" to XpPrefs.WAKE_PATH,
            "bcast" to XpPrefs.BCAST_PATH,
        )
        // label|path 列表，一行扫完，避免多次 fork
        val list = specs.joinToString("\n") { "${it.first}|${it.second}" }
        val script =
            """
            now=$(date +%s 2>/dev/null || echo 0)
            while IFS='|' read -r label f; do
              [ -n "${'$'}label" ] || continue
              if [ -f "${'$'}f" ]; then
                mt=$(stat -c %Y "${'$'}f" 2>/dev/null || echo 0)
                age=$((now - mt))
                prev=$(tr -d '\r' <"${'$'}f" 2>/dev/null | head -n1 | cut -c1-48)
                printf '1|%s|%s|%s|%s\n' "${'$'}label" "${'$'}age" "${'$'}prev" "${'$'}f"
              else
                printf '0|%s|||\n' "${'$'}label"
              fi
            done <<'QSC_BUS'
            $list
            QSC_BUS
            """.trimIndent()
        val r = root.exec(script)
        if (r.out.isBlank()) return emptyList()
        return r.out.lineSequence().mapNotNull { line ->
            val p = line.split('|', limit = 5)
            if (p.size < 2) return@mapNotNull null
            val present = p[0] == "1"
            val label = p.getOrNull(1).orEmpty()
            if (label.isEmpty()) return@mapNotNull null
            val age = p.getOrNull(2)?.toLongOrNull()?.takeIf { it >= 0 }
            val preview = p.getOrNull(3).orEmpty()
            val path = p.getOrNull(4) ?: specs.find { it.first == label }?.second.orEmpty()
            BusFileSnap(label = label, path = path, present = present, ageSec = age, preview = preview)
        }.toList()
    }

    private data class LsposedCfg(
        val enabled: Boolean,
        val scopedAndroid: Boolean,
        val scopeKnown: Boolean,
    )

    private suspend fun readLsposedConfigDb(
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
            return LsposedCfg(enabled = false, scopedAndroid = false, scopeKnown = false)
        }

        return try {
            SQLiteDatabase.openDatabase(
                local.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            ).use { db -> parseLsposedDb(db, ourPkgs) }
        } catch (_: Throwable) {
            LsposedCfg(enabled = false, scopedAndroid = false, scopeKnown = false)
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
                        if (c.getString(0)?.trim().equals(XpPrefs.PRIMARY_SCOPE, ignoreCase = true)) {
                            scoped = true
                            break
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

    fun isAvailable(context: Context): Boolean = isManagerInstalled(context)

    private suspend fun probeAliveFromXpLog(root: RootBridge): Boolean {
        val paths = listOf(
            "/data/system/qsc_xp.log",
            "/data/local/tmp/qsc_xp.log",
            "/cache/qsc_xp.log",
            "/data/adb/modules/QSC_Battery/data/xp.log",
        ).joinToString(" ") { "'$it'" }
        val r = root.exec(
            """
            for f in $paths; do
              [ -f "${'$'}f" ] || continue
              if grep -E 'ok loaded in system_server|ok alive|BatteryService hooked' "${'$'}f" >/dev/null 2>&1; then
                echo HIT
                exit 0
              fi
            done
            echo MISS
            """.trimIndent(),
        )
        return r.out.contains("HIT")
    }
}
