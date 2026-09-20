package com.qsc.battery.xposed

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.github.libxposed.api.XposedInterface
import io.github.libxposed.api.XposedModule
import io.github.libxposed.api.XposedModuleInterface.HotReloadingParam
import io.github.libxposed.api.XposedModuleInterface.ModuleLoadedParam
import io.github.libxposed.api.XposedModuleInterface.SystemServerStartingParam
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * LSPosed：仅系统框架。
 * 1) qscd 不可用时插拔边沿写 [XpPrefs.WAKE_PATH]（需 arm）
 * 2) 前台包名总线 [XpPrefs.FG_PATH] + 管理器进出 [XpPrefs.VIEWER_PATH]
 *    管理器会话：进出各经 3s 稳定；确认离开后再等 90s 超时才发 leave。
 *    会话仍在（含宽限）时切回管理器不重复 enter。
 * 不写充电节点。
 */
class QscXposedModule : XposedModule() {
    private val hookedBattery = AtomicBoolean(false)
    private val hookedActivity = AtomicBoolean(false)
    private val writeDisabled = AtomicBoolean(false)
    private val failStreak = AtomicInteger(0)
    private val armCacheAt = AtomicLong(0L)
    private val armCached = AtomicBoolean(false)
    private var lastPlugged: Boolean? = null
    private val fgBusFirstOk = AtomicBoolean(false)
    private val lastViewerLogAt = AtomicLong(0L)
    private val lastViewerLogMsg = AtomicReference<String?>(null)

    private val lastFgPkg = AtomicReference<String?>(null)
    /** 已确认的管理器观看会话（含离开后的 90s 宽限，直到 leave 落盘） */
    private val managerSession = AtomicBoolean(false)
    private val enterPending = AtomicBoolean(false)
    private val leavePending = AtomicBoolean(false)
    private val pendingLeavePkg = AtomicReference<String?>(null)
    private val viewerPkgsCacheAt = AtomicLong(0L)
    private val viewerPkgsCached = AtomicReference<Set<String>>(emptySet())

    private val fgHandler = Handler(Looper.getMainLooper())
    private var enterStableRunnable: Runnable? = null
    private var leaveStableRunnable: Runnable? = null
    private var leaveTimeoutRunnable: Runnable? = null
    private var fgStableRunnable: Runnable? = null

    override fun onModuleLoaded(param: ModuleLoadedParam) {
        if (!param.isSystemServer) {
            runCatching { detach() }
            return
        }
        xpLog(Log.INFO, "ok loaded in system_server api=$apiVersion process=${param.processName}")
        writeAliveOnce()
    }

    override fun onSystemServerStarting(param: SystemServerStartingParam) {
        writeAliveOnce()
        hookBatteryService(param.classLoader)
        hookActivityForeground(param.classLoader)
    }

    override fun onHotReloading(param: HotReloadingParam): Boolean {
        xpLog(Log.INFO, "refuse hot reload (system_server); reboot required")
        return false
    }

    private fun hookBatteryService(loader: ClassLoader) {
        if (!hookedBattery.compareAndSet(false, true)) return
        runCatching {
            val cls = loader.loadClass("com.android.server.BatteryService")
            val methods = cls.declaredMethods.filter { it.name == "processValuesLocked" }
            if (methods.isEmpty()) {
                xpLog(Log.WARN, "processValuesLocked missing")
                return
            }
            for (method in methods) {
                runCatching { deoptimize(method) }
                    .onFailure { xpLog(Log.DEBUG, "deoptimize skip: ${it.message}") }
                hook(method)
                    .setPriority(XposedInterface.PRIORITY_DEFAULT)
                    .setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept { chain ->
                        val result = chain.proceed()
                        val host = runCatching { chain.thisObject }.getOrNull()
                        onBatteryProcessed(host)
                        result
                    }
            }
            xpLog(Log.INFO, "ok BatteryService hooked x${methods.size} (deoptimize attempted)")
        }.onFailure {
            hookedBattery.set(false)
            xpLog(Log.ERROR, "hook failed: ${it.message}", it)
        }
    }

    private fun hookActivityForeground(loader: ClassLoader) {
        if (!hookedActivity.compareAndSet(false, true)) return
        var hooked = 0
        hooked += hookActivityRecordSetState(loader, "com.android.server.wm.ActivityRecord")
        hooked += hookActivityRecordSetState(loader, "com.android.server.am.ActivityRecord")
        hooked += hookResumedActivitySetter(loader, "com.android.server.wm.ActivityTaskManagerService")
        if (hooked > 0) {
            xpLog(Log.INFO, "ok activity foreground hooked sites=$hooked")
        } else {
            hookedActivity.set(false)
            xpLog(Log.WARN, "activity foreground hook: no matching methods")
        }
    }

    private fun hookActivityRecordSetState(loader: ClassLoader, className: String): Int {
        return runCatching {
            val cls = loader.loadClass(className)
            val methods = cls.declaredMethods.filter { it.name == "setState" && it.parameterTypes.isNotEmpty() }
            var n = 0
            for (method in methods) {
                runCatching { deoptimize(method) }
                hook(method)
                    .setPriority(XposedInterface.PRIORITY_DEFAULT)
                    .setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept { chain ->
                        val result = chain.proceed()
                        val ar = runCatching { chain.thisObject }.getOrNull() ?: return@intercept result
                        if (!isActivityCurrentlyResumed(ar)) return@intercept result
                        val pkg = activityPackage(ar) ?: return@intercept result
                        onForegroundPackage(pkg)
                        result
                    }
                n++
            }
            if (n > 0) xpLog(Log.DEBUG, "setState hooked $className x$n")
            n
        }.getOrElse {
            xpLog(Log.DEBUG, "setState skip $className: ${it.message}")
            0
        }
    }

    private fun hookResumedActivitySetter(loader: ClassLoader, className: String): Int {
        // 部分机型无 setState 可见性时的兜底：仅依赖 proceed 后 ATMS 焦点旁路较难取参，
        // 这里用同名方法 reflection 再调一次不安全；改为尝试 hook 后从第 0 个参数反射读取。
        return runCatching {
            val cls = loader.loadClass(className)
            val methods = cls.declaredMethods.filter {
                it.name == "setResumedActivityUncheckLocked" && it.parameterTypes.isNotEmpty()
            }
            var n = 0
            for (method in methods) {
                runCatching { deoptimize(method) }
                val param0 = method.parameterTypes[0]
                hook(method)
                    .setPriority(XposedInterface.PRIORITY_DEFAULT)
                    .setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept { chain ->
                        val result = chain.proceed()
                        // libxposed HookChain：优先 getArg；没有则跳过本站点
                        val ar = runCatching {
                            val m = chain.javaClass.methods.firstOrNull {
                                it.name == "getArg" && it.parameterCount == 1
                            }
                            m?.invoke(chain, 0)
                        }.getOrNull() ?: runCatching {
                            val f = chain.javaClass.methods.firstOrNull {
                                (it.name == "getArgs" || it.name == "args") && it.parameterCount == 0
                            }
                            val arr = f?.invoke(chain) as? Array<*>
                            arr?.getOrNull(0)
                        }.getOrNull()
                        if (ar == null || !param0.isInstance(ar)) return@intercept result
                        val pkg = activityPackage(ar) ?: return@intercept result
                        onForegroundPackage(pkg)
                        result
                    }
                n++
            }
            if (n > 0) xpLog(Log.DEBUG, "setResumedActivityUncheckLocked hooked $className x$n")
            n
        }.getOrElse {
            xpLog(Log.DEBUG, "setResumedActivityUncheckLocked skip $className: ${it.message}")
            0
        }
    }

    private fun isActivityCurrentlyResumed(ar: Any): Boolean {
        runCatching {
            val m = ar.javaClass.methods.firstOrNull { it.name == "getState" && it.parameterCount == 0 }
            val state = m?.invoke(ar) ?: return@runCatching
            return isResumedState(state)
        }
        for (name in arrayOf("mState", "state", "mActivityState")) {
            runCatching {
                val f = findField(ar.javaClass, name) ?: return@runCatching
                f.isAccessible = true
                val state = f.get(ar) ?: return@runCatching
                return isResumedState(state)
            }
        }
        // 读不到状态就别当 RESUMED，避免 setState(任意态) 刷屏写边沿
        return false
    }

    private fun isResumedState(state: Any): Boolean {
        val name = runCatching { (state as? Enum<*>)?.name ?: state.toString() }.getOrNull() ?: return false
        return name.contains("RESUMED", ignoreCase = true)
    }

    private fun activityPackage(ar: Any?): String? {
        if (ar == null) return null
        runCatching {
            val f = findField(ar.javaClass, "packageName") ?: return@runCatching
            f.isAccessible = true
            val v = f.get(ar) as? String
            if (!v.isNullOrBlank()) return v
        }
        runCatching {
            val f = findField(ar.javaClass, "mActivityComponent") ?: return@runCatching
            f.isAccessible = true
            val comp = f.get(ar) ?: return@runCatching
            val pkg = runCatching {
                comp.javaClass.getMethod("getPackageName").invoke(comp) as? String
            }.getOrNull()
            if (!pkg.isNullOrBlank()) return pkg
        }
        runCatching {
            val f = findField(ar.javaClass, "intent") ?: return@runCatching
            f.isAccessible = true
            val intent = f.get(ar) ?: return@runCatching
            val comp = intent.javaClass.getMethod("getComponent").invoke(intent) ?: return@runCatching
            val pkg = comp.javaClass.getMethod("getPackageName").invoke(comp) as? String
            if (!pkg.isNullOrBlank()) return pkg
        }
        runCatching {
            val f = findField(ar.javaClass, "info") ?: return@runCatching
            f.isAccessible = true
            val info = f.get(ar) ?: return@runCatching
            val pkgField = findField(info.javaClass, "packageName") ?: return@runCatching
            pkgField.isAccessible = true
            val v = pkgField.get(info) as? String
            if (!v.isNullOrBlank()) return v
        }
        return null
    }

    private fun onForegroundPackage(pkg: String) {
        if (writeDisabled.get()) return
        if (File(XpPrefs.OFF_PATH).isFile) return
        if (File(XpPrefs.NO_VIEWER_PATH).isFile) return
        val clean = pkg.trim()
        if (clean.isEmpty()) return
        val prev = lastFgPkg.getAndSet(clean)
        if (prev == clean) return

        val wantManager = isManagerPackage(clean)
        if (wantManager) {
            cancelLeavePipeline()
            cancelFgStableDebounce()
            // 会话仍在（含 90s 宽限）：轮询应还在跑，只更新 fg，不重复 enter
            if (managerSession.get()) {
                writeFg(clean, notifyEdge = true)
                xpLog(Log.DEBUG, "viewer session keep ($clean)")
                return
            }
            writeFg(clean, notifyEdge = false)
            scheduleEnterStable(clean)
            return
        }

        cancelEnterStable()
        if (managerSession.get()) {
            // 会话中离开：fg 立刻更新；3s 稳定后再开 90s 超时，到点才 leave
            cancelFgStableDebounce()
            writeFg(clean, notifyEdge = true)
            scheduleLeavePipeline(clean)
            return
        }

        // 普通 App 切换：短防抖后再落盘，避免 A↔B 连切刷边沿
        scheduleFgStableDebounce(clean)
    }

    private fun cancelEnterStable() {
        enterStableRunnable?.let { fgHandler.removeCallbacks(it) }
        enterStableRunnable = null
        enterPending.set(false)
    }

    private fun cancelLeavePipeline() {
        leaveStableRunnable?.let { fgHandler.removeCallbacks(it) }
        leaveTimeoutRunnable?.let { fgHandler.removeCallbacks(it) }
        leaveStableRunnable = null
        leaveTimeoutRunnable = null
        leavePending.set(false)
        pendingLeavePkg.set(null)
    }

    private fun cancelFgStableDebounce() {
        fgStableRunnable?.let { fgHandler.removeCallbacks(it) }
        fgStableRunnable = null
    }

    /** 进入管理器：3s 稳定后才确认会话并写 enter */
    private fun scheduleEnterStable(pkg: String) {
        if (enterPending.get()) {
            return
        }
        enterPending.set(true)
        val r = Runnable {
            enterStableRunnable = null
            enterPending.set(false)
            if (managerSession.get()) return@Runnable
            val cur = lastFgPkg.get() ?: return@Runnable
            if (!isManagerPackage(cur)) return@Runnable
            if (!managerSession.compareAndSet(false, true)) return@Runnable
            writeFg(cur, notifyEdge = true)
            writeViewerEdge("enter", cur)
            xpLog(Log.DEBUG, "viewer enter stable ($cur)")
        }
        enterStableRunnable = r
        fgHandler.postDelayed(r, MANAGER_STABLE_MS)
        xpLog(Log.DEBUG, "viewer enter scheduled ${MANAGER_STABLE_MS}ms ($pkg)")
    }

    /**
     * 离开管理器：先 3s 稳定确认离开，再等 [MANAGER_LEAVE_TIMEOUT_MS] 超时才写 leave。
     * 宽限期内切回管理器会 cancel，会话不中断、不重复 enter。
     */
    private fun scheduleLeavePipeline(pkg: String) {
        pendingLeavePkg.set(pkg)
        if (leavePending.get()) {
            return
        }
        leavePending.set(true)
        val stable = Runnable {
            leaveStableRunnable = null
            val leavePkg = pendingLeavePkg.get() ?: pkg
            val cur = lastFgPkg.get()
            if (cur != null && isManagerPackage(cur)) {
                leavePending.set(false)
                pendingLeavePkg.set(null)
                return@Runnable
            }
            if (!managerSession.get()) {
                leavePending.set(false)
                pendingLeavePkg.set(null)
                return@Runnable
            }
            xpLog(Log.DEBUG, "viewer leave stable, timeout ${MANAGER_LEAVE_TIMEOUT_MS}ms ($leavePkg)")
            val timeout = Runnable {
                leaveTimeoutRunnable = null
                leavePending.set(false)
                val finalPkg = pendingLeavePkg.getAndSet(null) ?: leavePkg
                val now = lastFgPkg.get()
                if (now != null && isManagerPackage(now)) return@Runnable
                if (managerSession.compareAndSet(true, false)) {
                    writeFg(finalPkg, notifyEdge = true)
                    writeViewerEdge("leave", finalPkg)
                    xpLog(Log.DEBUG, "viewer leave timeout ($finalPkg)")
                }
            }
            leaveTimeoutRunnable = timeout
            fgHandler.postDelayed(timeout, MANAGER_LEAVE_TIMEOUT_MS)
        }
        leaveStableRunnable = stable
        fgHandler.postDelayed(stable, MANAGER_STABLE_MS)
        xpLog(Log.DEBUG, "viewer leave stable scheduled ${MANAGER_STABLE_MS}ms ($pkg)")
    }

    private fun scheduleFgStableDebounce(pkg: String) {
        cancelFgStableDebounce()
        val r = Runnable {
            fgStableRunnable = null
            if (managerSession.get() || leavePending.get() || enterPending.get()) return@Runnable
            if (lastFgPkg.get() != pkg) return@Runnable
            writeFg(pkg, notifyEdge = true)
        }
        fgStableRunnable = r
        fgHandler.postDelayed(r, FG_STABLE_DEBOUNCE_MS)
    }

    private fun writeFg(pkg: String, notifyEdge: Boolean) {
        if (writeDisabled.get()) return
        val line = "${System.currentTimeMillis()}\t$pkg\n"
        val okFg = writeText(XpPrefs.FG_PATH, line, append = false)
        val okEdge = if (notifyEdge) {
            writeText(XpPrefs.FG_EDGE_PATH, line, append = false)
        } else {
            false
        }
        if (okFg || okEdge) {
            failStreak.set(0)
            if (fgBusFirstOk.compareAndSet(false, true)) {
                xpLog(Log.INFO, "ok fg-bus ready (first=$pkg)")
            } else {
                xpLog(Log.DEBUG, "fg $pkg")
            }
        } else {
            onWriteFailed("fg:$pkg")
            xpLog(Log.WARN, "fg write failed ($pkg)")
        }
    }

    private fun isManagerPackage(pkg: String): Boolean {
        if (BUILTIN_MANAGER_PKGS.contains(pkg)) return true
        return loadViewerPkgs().contains(pkg)
    }

    private fun loadViewerPkgs(): Set<String> {
        val now = System.currentTimeMillis()
        if (now - viewerPkgsCacheAt.get() < VIEWER_PKGS_CACHE_MS) {
            return viewerPkgsCached.get()
        }
        viewerPkgsCacheAt.set(now)
        val set = linkedSetOf<String>()
        runCatching {
            val f = File(XpPrefs.VIEWER_PKGS_PATH)
            if (!f.isFile) return@runCatching
            f.readLines().forEach { line ->
                val p = line.trim()
                if (p.isNotEmpty() && !p.startsWith("#") && p.all { it.isLetterOrDigit() || it == '.' || it == '_' }) {
                    set.add(p)
                }
            }
        }
        viewerPkgsCached.set(set)
        return set
    }

    private fun writeViewerEdge(edge: String, pkg: String) {
        if (writeDisabled.get()) return
        val ok = writeText(
            XpPrefs.VIEWER_PATH,
            "${System.currentTimeMillis()}\t$edge\t$pkg\n",
            append = false,
        )
        if (ok) {
            failStreak.set(0)
            // 管理器进出：INFO，但对相同文案做短去抖，避免亮灭闪一下刷两行
            logViewerInfoOnce("ok viewer $edge $pkg")
        } else {
            onWriteFailed("viewer:$edge")
            xpLog(Log.WARN, "viewer write failed ($edge $pkg)")
        }
    }

    /** 相同 INFO 在 VIEWER_LOG_DEBOUNCE_MS 内只落一次 */
    private fun logViewerInfoOnce(msg: String) {
        val now = System.currentTimeMillis()
        if (msg == lastViewerLogMsg.get() &&
            now - lastViewerLogAt.get() < VIEWER_LOG_DEBOUNCE_MS
        ) {
            xpLog(Log.DEBUG, "dup $msg")
            return
        }
        lastViewerLogMsg.set(msg)
        lastViewerLogAt.set(now)
        xpLog(Log.INFO, msg)
    }

    private fun onBatteryProcessed(service: Any?) {
        if (writeDisabled.get()) return
        if (File(XpPrefs.OFF_PATH).isFile) return
        if (File(XpPrefs.NO_WAKE_PATH).isFile) return
        if (!isArmedCached()) return

        val plugged = readPluggedFromService(service) ?: readPluggedSysfs()
        val prev = lastPlugged
        lastPlugged = plugged
        if (prev == null || prev == plugged) return

        writeWake(if (plugged) "plug" else "unplug")
    }

    private fun isArmedCached(): Boolean {
        val now = System.currentTimeMillis()
        if (armCached.get()) {
            if (File(XpPrefs.ARM_PATH).isFile) return true
            armCached.set(false)
            armCacheAt.set(now)
            return false
        }
        if (now - armCacheAt.get() < ARM_RECHECK_MS) return false
        armCacheAt.set(now)
        val on = File(XpPrefs.ARM_PATH).isFile
        armCached.set(on)
        return on
    }

    /** 优先 BatteryService 内部状态，失败再 sysfs。 */
    private fun readPluggedFromService(service: Any?): Boolean? {
        if (service == null) return null
        runCatching {
            val f = findField(service.javaClass, "mPlugType") ?: return@runCatching
            f.isAccessible = true
            return f.getInt(service) != 0
        }
        runCatching {
            val hiField = findField(service.javaClass, "mHealthInfo") ?: return@runCatching
            hiField.isAccessible = true
            val hi = hiField.get(service) ?: return@runCatching
            val cls = hi.javaClass
            fun flag(name: String): Boolean = runCatching {
                val f = findField(cls, name) ?: return false
                f.isAccessible = true
                f.getBoolean(hi)
            }.getOrDefault(false)
            val plugged = flag("chargerAcOnline") || flag("chargerUsbOnline") ||
                flag("chargerWirelessOnline") || flag("chargerDockOnline")
            return plugged
        }
        return null
    }

    private fun findField(cls: Class<*>, name: String): java.lang.reflect.Field? {
        var c: Class<*>? = cls
        while (c != null) {
            runCatching { return c.getDeclaredField(name) }
            c = c.superclass
        }
        return null
    }

    private fun readPluggedSysfs(): Boolean {
        for (path in PLUG_ONLINE_PATHS) {
            val v = runCatching { File(path).readText().trim() }.getOrNull() ?: continue
            if (v == "1") return true
        }
        return false
    }

    private fun writeAliveOnce() {
        if (writeDisabled.get()) return
        val content = "${System.currentTimeMillis()}\talive\n"
        var ok = false
        for (path in ALIVE_PATHS) {
            if (writeText(path, content, append = false)) {
                ok = true
                xpLog(Log.INFO, "ok alive → $path")
            }
        }
        if (ok) {
            failStreak.set(0)
        } else {
            onWriteFailed("alive")
            xpLog(Log.WARN, "alive write failed all paths")
        }
    }

    private fun writeWake(reason: String) {
        if (writeDisabled.get()) return
        val ok = writeText(XpPrefs.WAKE_PATH, "${System.currentTimeMillis()}\t$reason\n", append = false)
        if (ok) {
            failStreak.set(0)
            xpLog(Log.INFO, "ok wake $reason → ${XpPrefs.WAKE_PATH}")
        } else {
            onWriteFailed("wake:$reason")
            xpLog(Log.WARN, "wake write failed ($reason)")
        }
    }

    private fun onWriteFailed(what: String) {
        val n = failStreak.incrementAndGet()
        if (n >= 2) {
            writeDisabled.set(true)
            xpLog(Log.WARN, "write disabled for this boot after failures ($what)")
        }
    }

    private fun writeText(path: String, content: String, append: Boolean): Boolean {
        return try {
            val f = File(path)
            val parent = f.parentFile ?: return false
            if (!parent.exists() && !parent.mkdirs()) return false
            FileOutputStream(f, append).use { it.write(content.toByteArray()) }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun appendLogLine(priority: Int, msg: String) {
        if (priority == Log.DEBUG && !File(XpPrefs.VERBOSE_PATH).isFile) return
        val level = when (priority) {
            Log.ERROR -> "ERROR"
            Log.WARN -> "WARN"
            Log.DEBUG -> "DEBUG"
            else -> "INFO"
        }
        val line = "${System.currentTimeMillis()}\t$level\t$msg\n"
        val bytes = line.toByteArray()
        var wrote = false
        for (path in LOG_PATHS) {
            runCatching {
                val f = File(path)
                f.parentFile?.mkdirs()
                FileOutputStream(f, true).use { it.write(bytes) }
                if (f.length() > LOG_MAX_BYTES) {
                    val keep = f.readBytes().let { body ->
                        val start = (body.size - LOG_KEEP_BYTES).coerceAtLeast(0)
                        body.copyOfRange(start, body.size)
                    }
                    FileOutputStream(f, false).use { it.write(keep) }
                }
                wrote = true
            }
        }
        if (!wrote) Log.w(TAG, "xp file log write failed all paths: $msg")
    }

    private fun xpLog(priority: Int, msg: String, tr: Throwable? = null) {
        if (tr != null) log(priority, TAG, msg, tr) else log(priority, TAG, msg)
        appendLogLine(priority, if (tr != null) "$msg (${tr.javaClass.simpleName})" else msg)
    }

    companion object {
        private const val TAG = "QscXp"
        private const val ARM_RECHECK_MS = 60_000L
        private const val VIEWER_PKGS_CACHE_MS = 60_000L
        private const val VIEWER_LOG_DEBOUNCE_MS = 2_000L
        /** 进出管理器边沿稳定时间（防抖） */
        private const val MANAGER_STABLE_MS = 3_000L
        /** 确认离开后再等此时长才发 leave（会话超时） */
        private const val MANAGER_LEAVE_TIMEOUT_MS = 90_000L
        /** 普通 App 前台落盘稳定时间（≈800ms，与列表墓碑进入对齐） */
        private const val FG_STABLE_DEBOUNCE_MS = 800L
        private const val LOG_MAX_BYTES = 48_000L
        private const val LOG_KEEP_BYTES = 24_000

        private val LOG_PATHS = listOf(
            "/data/system/qsc_xp.log",
            "/data/local/tmp/qsc_xp.log",
            "/cache/qsc_xp.log",
        )

        private val ALIVE_PATHS = listOf(
            "/data/system/qsc_xp_alive",
            "/data/local/tmp/qsc_xp_alive",
            "/cache/qsc_xp_alive",
            "/data/adb/modules/QSC_Battery/data/xp_alive",
        )

        private val PLUG_ONLINE_PATHS = listOf(
            "/sys/class/power_supply/usb/online",
            "/sys/class/power_supply/usb/present",
            "/sys/class/power_supply/pc_port/online",
            "/sys/class/power_supply/ac/online",
            "/sys/class/power_supply/wireless/online",
            "/sys/class/power_supply/dc/online",
        )

        /** 与 module/bin/lib/manager_viewers.sh 内置表保持同步（冷启动尚无 pkgs 文件时也能命中） */
        private val BUILTIN_MANAGER_PKGS = setOf(
            "com.topjohnwu.magisk",
            "io.github.vvb2060.magisk",
            "io.github.huskydg.magisk",
            "com.rifsxd.ksunext",
            "me.weishu.kernelsu",
            "com.tiann.kernelsu",
            "com.sukisu.ultra",
            "com.resukisu.resukisu",
            "me.bmax.apatch",
            "me.garfieldhan.apatch.next",
            "me.yuki.folk",
            "com.dergoogler.mmrl",
            "com.dergoogler.mmrl.wx",
            "com.dergoogler.mmrl.ksuwebui",
            "io.github.a13e300.ksuwebui",
            "com.yujincheng1994.wx",
        )
    }
}
