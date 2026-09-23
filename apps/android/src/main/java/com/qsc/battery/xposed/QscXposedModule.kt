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
 *    Magisk 写 [XpPrefs.FG_POLICY_PATH] 门禁：无简介/游戏/停充则 idle，XP 不写盘。
 *    分级：仅简介→管理器；游戏/停充→各自列表；离开关注包仍写一次。
 *    管理器会话：进出各经 3s 稳定；离开稳定后立即写 leave（包名为管理器）。
 *    边沿文件追加队列，避免 enter 被 leave 覆盖。切回管理器会补发 enter。
 * 3) 可选辅助边沿（默认关）：亮灭屏 / Doze / 白名单广播 → [QscXpAssist]
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

    /** 上一帧 isInteractive；亮灭屏边沿用于重发管理器 enter */
    private val lastInteractive = AtomicReference<Boolean?>(null)

    /** 上一前台是否属于策略关注包（用于离开时仍写一次 fg） */
    private val lastWasWatch = AtomicBoolean(false)

    /** 已确认的管理器观看会话（含离开防抖，直到 leave 落盘） */
    private val managerSession = AtomicBoolean(false)
    private val enterPending = AtomicBoolean(false)
    private val leavePending = AtomicBoolean(false)
    /** 离开管线里暂存「切去的包」；leave 边沿仍写 [lastManagerPkg] */
    private val pendingLeaveToPkg = AtomicReference<String?>(null)
    /** 最近一次确认 enter 的管理器包名（leave 日志/边沿用它，勿写成 launcher） */
    private val lastManagerPkg = AtomicReference<String?>(null)
    private val viewerPkgsCacheAt = AtomicLong(0L)
    private val viewerPkgsCached = AtomicReference<Set<String>>(emptySet())
    private val viewerPkgsMtime = AtomicLong(-1L)
    private val gamePkgsCacheAt = AtomicLong(0L)
    private val gamePkgsCached = AtomicReference<Set<String>>(emptySet())
    private val gamePkgsMtime = AtomicLong(-1L)
    private val stopPkgsCacheAt = AtomicLong(0L)
    private val stopPkgsCached = AtomicReference<Set<String>>(emptySet())
    private val stopPkgsMtime = AtomicLong(-1L)
    private val policyCacheAt = AtomicLong(0L)
    private val policyCached = AtomicReference(FgPolicy.DEFAULT)
    private val verboseCacheAt = AtomicLong(0L)
    private val verboseCached = AtomicBoolean(false)
    private val fgIdleCacheAt = AtomicLong(0L)
    private val fgIdleCached = AtomicBoolean(false)

    private val fgHandler = Handler(Looper.getMainLooper())
    private var enterStableRunnable: Runnable? = null
    private var leaveStableRunnable: Runnable? = null
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
        QscXpAssist.install(this, param.classLoader, { p, m -> xpLog(p, m) }) { on ->
            onInteractiveChanged(on)
        }
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
                        // idle：跳过反射取包名
                        if (isFgIdleFast()) return@intercept result
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
            // 新系统 ActivityRecord 在 wm，am 路径必缺；只记短句，避免 ClassNotFound 带整段 DexPathList
            val short = when {
                it is ClassNotFoundException || it.message?.contains("Didn't find class") == true ->
                    "class missing (ok on modern Android)"

                else -> it.message?.take(120) ?: it.javaClass.simpleName
            }
            xpLog(Log.DEBUG, "setState skip $className: $short")
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
                        if (isFgIdleFast()) return@intercept result
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
            val short = when {
                it is ClassNotFoundException || it.message?.contains("Didn't find class") == true ->
                    "class missing"

                else -> it.message?.take(120) ?: it.javaClass.simpleName
            }
            xpLog(Log.DEBUG, "setResumedActivityUncheckLocked skip $className: $short")
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

    private fun isInteractive(): Boolean {
        return runCatching {
            val pmClass = Class.forName("android.os.PowerManager")
            // system_server: ActivityManagerService 等同进程可读 PowerManagerService 内部；
            // 更稳：通过 Context 拿 PowerManager（XposedModule 可能无 app context）
            val ctx = runCatching {
                val at = Class.forName("android.app.ActivityThread")
                val cur = at.getMethod("currentActivityThread").invoke(null)
                at.getMethod("getSystemContext").invoke(cur)
            }.getOrNull() ?: return@runCatching true
            val pm = ctx.javaClass.getMethod("getSystemService", String::class.java)
                .invoke(ctx, "power") ?: return@runCatching true
            val m = pm.javaClass.methods.firstOrNull {
                it.name == "isInteractive" && it.parameterCount == 0
            } ?: pm.javaClass.methods.firstOrNull {
                it.name == "isScreenOn" && it.parameterCount == 0
            }
            (m?.invoke(pm) as? Boolean) ?: true
        }.getOrDefault(true)
    }

    /**
     * 亮灭屏边沿（不依赖 want_screen）。
     * 管理器仍在前台时息屏→亮屏，AMS 常不重抛前台切换；必须在此补 leave/enter，
     * 否则简介 worker 会停在静态文案。
     */
    private fun onInteractiveChanged(on: Boolean) {
        if (writeDisabled.get()) return
        if (File(XpPrefs.OFF_PATH).isFile) return
        if (File(XpPrefs.NO_VIEWER_PATH).isFile) return
        val prev = lastInteractive.getAndSet(on)
        if (prev != null && prev == on) return

        val policy = loadFgPolicy()
        if (policy.idle || !policy.desc) return
        val pkg = lastFgPkg.get()?.trim().orEmpty()

        if (!on) {
            cancelEnterStable()
            if (managerSession.get()) {
                cancelFgStableDebounce()
                scheduleLeavePipeline(pkg.ifEmpty { "screen_off" })
            }
            return
        }

        // 亮屏：宽限期内取消 leave；会话已结束则重进；会话仍在则补发 enter 唤醒 worker
        if (pkg.isNotEmpty() && isManagerPackage(pkg)) {
            cancelLeavePipeline()
            cancelFgStableDebounce()
            if (managerSession.get()) {
                writeManagerFg(pkg)
                lastManagerPkg.set(pkg)
                writeViewerEdge("enter", pkg)
                lastWasWatch.set(true)
                xpLog(Log.DEBUG, "viewer pulse enter on screen on ($pkg)")
            } else {
                writeManagerFg(pkg)
                scheduleEnterStable(pkg)
            }
        }
    }

    private fun onForegroundPackage(pkg: String) {
        if (writeDisabled.get()) return
        if (File(XpPrefs.OFF_PATH).isFile) return
        if (File(XpPrefs.NO_VIEWER_PATH).isFile) return
        val clean = pkg.trim()
        if (clean.isEmpty()) return

        val policy = loadFgPolicy()
        if (policy.idle) {
            // 简介/游戏/停充均关：不写盘、不排程
            cancelEnterStable()
            cancelLeavePipeline()
            cancelFgStableDebounce()
            if (managerSession.getAndSet(false)) {
                xpLog(Log.DEBUG, "fg policy idle, drop manager session")
            }
            lastFgPkg.set(clean)
            lastWasWatch.set(false)
            return
        }

        val interactive = isInteractive()
        val prevInteractive = lastInteractive.getAndSet(interactive)
        val prev = lastFgPkg.getAndSet(clean)
        val samePkg = prev == clean
        // 同包名通常忽略；但亮屏边沿必须放行（息屏后再亮时 AMS 往往不再抛前台切换）
        val screenJustOn = prevInteractive == false && interactive
        if (samePkg && !screenJustOn) return

        val wantManager = policy.desc && isManagerPackage(clean)
        val watchNow = wantManager ||
            (policy.game && isGamePackage(clean)) ||
            (policy.appStop && isStopPackage(clean))

        // 息屏：不允许新进管理器会话；若已在会话则走离开管线
        if (!interactive) {
            cancelEnterStable()
            if (policy.desc && managerSession.get()) {
                cancelFgStableDebounce()
                scheduleLeavePipeline(clean)
            }
            if (watchNow || lastWasWatch.get()) {
                lastWasWatch.set(false)
                if (needFgBus(policy)) scheduleFgStableDebounce(clean)
            }
            return
        }

        if (wantManager) {
            val wasLeaving = leavePending.get()
            cancelLeavePipeline()
            cancelFgStableDebounce()
            if (managerSession.get()) {
                // 会话仍在（含离开宽限期取消回来 / 亮屏）：必须再发 enter，
                // 否则 worker 若已因 poll 失败退出观看循环，简介会一直停住。
                writeManagerFg(clean)
                writeViewerEdge("enter", clean)
                lastManagerPkg.set(clean)
                lastWasWatch.set(true)
                xpLog(
                    Log.DEBUG,
                    when {
                        screenJustOn -> "viewer pulse enter on screen on ($clean)"
                        wasLeaving -> "viewer pulse enter after leave cancel ($clean)"
                        else -> "viewer session pulse enter ($clean)"
                    },
                )
                return
            }
            writeManagerFg(clean)
            scheduleEnterStable(clean)
            return
        }

        cancelEnterStable()
        if (policy.desc && managerSession.get()) {
            cancelFgStableDebounce()
            // 离开管理器：先把 fg 改成当前包，避免 desc-only 下 fg 仍挂着管理器导致假阳性
            writeFg(clean, notifyEdge = needFgBus(policy))
            scheduleLeavePipeline(clean)
            return
        }

        // 进入或离开游戏/停充关注包才落盘；其它 App 切换零 I/O
        if (watchNow || lastWasWatch.get()) {
            lastWasWatch.set(watchNow)
            scheduleFgStableDebounce(clean)
            return
        }
        lastWasWatch.set(false)
    }

    private data class FgPolicy(
        val desc: Boolean,
        val game: Boolean,
        val appStop: Boolean,
        val idle: Boolean,
    ) {
        companion object {
            /** 策略文件尚未写出时：默认只开管理器边沿（与 description 默认开一致） */
            val DEFAULT = FgPolicy(desc = true, game = false, appStop = false, idle = false)
        }
    }

    private fun loadFgPolicy(): FgPolicy {
        val now = System.currentTimeMillis()
        if (now - policyCacheAt.get() < POLICY_CACHE_MS) {
            return policyCached.get()
        }
        policyCacheAt.set(now)
        val f = File(XpPrefs.FG_POLICY_PATH)
        if (!f.isFile) {
            policyCached.set(FgPolicy.DEFAULT)
            return FgPolicy.DEFAULT
        }
        var desc = false
        var game = false
        var appStop = false
        var idle = false
        runCatching {
            f.readLines().forEach { line ->
                val t = line.trim()
                when {
                    t.startsWith("desc=") -> desc = t.substringAfter('=') == "1"
                    t.startsWith("game=") -> game = t.substringAfter('=') == "1"
                    t.startsWith("app_stop=") -> appStop = t.substringAfter('=') == "1"
                    t.startsWith("idle=") -> idle = t.substringAfter('=') == "1"
                }
            }
        }
        if (!desc && !game && !appStop) idle = true
        val p = FgPolicy(desc, game, appStop, idle)
        policyCached.set(p)
        return p
    }

    private fun isVerbose(): Boolean {
        val now = System.currentTimeMillis()
        if (now - verboseCacheAt.get() < VERBOSE_CACHE_MS) {
            return verboseCached.get()
        }
        verboseCacheAt.set(now)
        val on = File(XpPrefs.VERBOSE_PATH).isFile
        verboseCached.set(on)
        return on
    }

    /** 热路径：优先看 idle 标记文件，再回落策略缓存 */
    private fun isFgIdleFast(): Boolean {
        val now = System.currentTimeMillis()
        if (now - fgIdleCacheAt.get() < FG_IDLE_CACHE_MS) {
            return fgIdleCached.get()
        }
        fgIdleCacheAt.set(now)
        val idle = File(XpPrefs.FG_IDLE_PATH).isFile ||
            File(XpPrefs.OFF_PATH).isFile ||
            File(XpPrefs.NO_VIEWER_PATH).isFile ||
            loadFgPolicy().idle
        fgIdleCached.set(idle)
        return idle
    }

    /** 游戏/停充需要通用前台总线；仅简介时也要给管理器写 fg，供 worker poll 命中 */
    private fun needFgBus(policy: FgPolicy): Boolean = policy.game || policy.appStop

    private fun writeFgIfNeeded(pkg: String, notifyEdge: Boolean, policy: FgPolicy) {
        when {
            needFgBus(policy) -> writeFg(pkg, notifyEdge)
            policy.desc && isManagerPackage(pkg) -> writeFg(pkg, notifyEdge = false)
        }
    }

    /** 管理器在前台：始终维护 qsc_xp_fg（即使仅开简介） */
    private fun writeManagerFg(pkg: String) {
        writeFg(pkg, notifyEdge = false)
    }

    private fun cancelEnterStable() {
        enterStableRunnable?.let { fgHandler.removeCallbacks(it) }
        enterStableRunnable = null
        enterPending.set(false)
    }

    private fun cancelLeavePipeline() {
        leaveStableRunnable?.let { fgHandler.removeCallbacks(it) }
        leaveStableRunnable = null
        leavePending.set(false)
        pendingLeaveToPkg.set(null)
    }

    private fun cancelFgStableDebounce() {
        fgStableRunnable?.let { fgHandler.removeCallbacks(it) }
        fgStableRunnable = null
    }

    /** 进入管理器：稳定后才确认会话并写 enter */
    private fun scheduleEnterStable(pkg: String) {
        if (enterPending.get()) {
            return
        }
        enterPending.set(true)
        val r = Runnable {
            enterStableRunnable = null
            enterPending.set(false)
            if (managerSession.get()) return@Runnable
            if (!isInteractive()) {
                xpLog(Log.DEBUG, "viewer enter skip: not interactive")
                return@Runnable
            }
            val cur = lastFgPkg.get() ?: return@Runnable
            if (!isManagerPackage(cur)) return@Runnable
            if (!managerSession.compareAndSet(false, true)) return@Runnable
            val p = loadFgPolicy()
            lastManagerPkg.set(cur)
            writeManagerFg(cur)
            if (needFgBus(p)) writeFg(cur, notifyEdge = true)
            writeViewerEdge("enter", cur)
            lastWasWatch.set(true)
            xpLog(Log.DEBUG, "viewer enter stable ($cur)")
        }
        enterStableRunnable = r
        fgHandler.postDelayed(r, MANAGER_STABLE_MS)
        xpLog(Log.DEBUG, "viewer enter scheduled ${MANAGER_STABLE_MS}ms ($pkg)")
    }

    /**
     * 离开管理器：经 [MANAGER_STABLE_MS] 确认后立即写 leave。
     * 边沿第三列始终为管理器包名（不是切去的 launcher/其它 App）。
     * 短暂误切再回来：cancelLeave + pulse enter，会话不中断。
     */
    private fun scheduleLeavePipeline(toPkg: String) {
        pendingLeaveToPkg.set(toPkg)
        if (leavePending.get()) {
            return
        }
        leavePending.set(true)
        val stable = Runnable {
            leaveStableRunnable = null
            val to = pendingLeaveToPkg.getAndSet(null) ?: toPkg
            leavePending.set(false)
            val cur = lastFgPkg.get()
            if (cur != null && isManagerPackage(cur)) {
                return@Runnable
            }
            if (!managerSession.compareAndSet(true, false)) {
                return@Runnable
            }
            val mgr = lastManagerPkg.get()?.takeIf { it.isNotBlank() } ?: "manager"
            val p = loadFgPolicy()
            // fg 指到当前前台（非管理器），便于 Magisk 用 fg 立刻判定已离开
            writeFg(to, notifyEdge = needFgBus(p))
            writeViewerEdge("leave", mgr)
            lastWasWatch.set(
                (p.game && isGamePackage(to)) ||
                    (p.appStop && isStopPackage(to)),
            )
            xpLog(Log.DEBUG, "viewer leave stable ($mgr → $to)")
        }
        leaveStableRunnable = stable
        fgHandler.postDelayed(stable, MANAGER_STABLE_MS)
        xpLog(Log.DEBUG, "viewer leave stable scheduled ${MANAGER_STABLE_MS}ms (to=$toPkg)")
    }

    private fun scheduleFgStableDebounce(pkg: String) {
        cancelFgStableDebounce()
        val r = Runnable {
            fgStableRunnable = null
            if (managerSession.get() || leavePending.get() || enterPending.get()) return@Runnable
            if (lastFgPkg.get() != pkg) return@Runnable
            writeFg(pkg, notifyEdge = true)
            val p = loadFgPolicy()
            lastWasWatch.set(
                (p.desc && isManagerPackage(pkg)) ||
                    (p.game && isGamePackage(pkg)) ||
                    (p.appStop && isStopPackage(pkg)),
            )
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
            val watched = isManagerPackage(pkg) || isGamePackage(pkg) || isStopPackage(pkg)
            val verbose = isVerbose()
            if (fgBusFirstOk.compareAndSet(false, true)) {
                // 首帧：关注包带包名；非关注不报包名（非详细），避免刷无关应用
                when {
                    watched -> xpLog(Log.INFO, "ok fg-bus ready (first=$pkg)")
                    verbose -> xpLog(Log.DEBUG, "ok fg-bus ready (first=$pkg)")
                    else -> xpLog(Log.INFO, "ok fg-bus ready")
                }
            } else if (verbose) {
                // 详细模式才逐条打前台切换；关注进出已有 viewer INFO
                xpLog(Log.DEBUG, "fg $pkg")
            }
        } else {
            onWriteFailed("fg")
            if (isVerbose()) {
                xpLog(Log.WARN, "fg write failed ($pkg)")
            } else {
                xpLog(Log.WARN, "fg write failed")
            }
        }
    }

    private fun isManagerPackage(pkg: String): Boolean {
        if (BUILTIN_MANAGER_PKGS.contains(pkg)) return true
        return loadPkgSet(
            XpPrefs.VIEWER_PKGS_PATH,
            viewerPkgsCacheAt,
            viewerPkgsCached,
            viewerPkgsMtime,
        ).contains(pkg)
    }

    private fun isGamePackage(pkg: String): Boolean = loadPkgSet(
        XpPrefs.GAME_PKGS_PATH,
        gamePkgsCacheAt,
        gamePkgsCached,
        gamePkgsMtime,
    ).contains(pkg)

    private fun isStopPackage(pkg: String): Boolean = loadPkgSet(
        XpPrefs.STOP_PKGS_PATH,
        stopPkgsCacheAt,
        stopPkgsCached,
        stopPkgsMtime,
    ).contains(pkg)

    private fun loadPkgSet(
        path: String,
        cacheAt: AtomicLong,
        cached: AtomicReference<Set<String>>,
        fileMtime: AtomicLong,
    ): Set<String> {
        val f = File(path)
        val mtime = runCatching { if (f.isFile) f.lastModified() else 0L }.getOrDefault(0L)
        val now = System.currentTimeMillis()
        // 文件未变且未过期才用缓存；Magisk 隐藏包名列表更新后须尽快生效
        if (now - cacheAt.get() < PKG_LIST_CACHE_MS && mtime == fileMtime.get()) {
            return cached.get()
        }
        cacheAt.set(now)
        fileMtime.set(mtime)
        val set = linkedSetOf<String>()
        runCatching {
            if (!f.isFile) return@runCatching
            f.readLines().forEach { line ->
                val p = line.trim()
                if (p.isNotEmpty() && !p.startsWith("#") &&
                    p.all { it.isLetterOrDigit() || it == '.' || it == '_' }
                ) {
                    set.add(p)
                }
            }
        }
        cached.set(set)
        return set
    }

    private fun writeViewerEdge(edge: String, pkg: String) {
        if (writeDisabled.get()) return
        // 追加队列：Magisk 睡着时 enter+leave 都能保留，勿覆盖成只剩最后一条
        trimViewerQueueIfHuge()
        val ok = writeText(
            XpPrefs.VIEWER_PATH,
            "${System.currentTimeMillis()}\t$edge\t$pkg\n",
            append = true,
        )
        if (ok) {
            failStreak.set(0)
            // leave 第三列是管理器包；INFO 去抖避免亮灭闪一下刷两行
            logViewerInfoOnce("ok viewer $edge $pkg")
        } else {
            onWriteFailed("viewer:$edge")
            xpLog(Log.WARN, "viewer write failed ($edge $pkg)")
        }
    }

    /** Magisk 长期未消费时防止队列膨胀；保留尾部若干行 */
    private fun trimViewerQueueIfHuge() {
        runCatching {
            val f = File(XpPrefs.VIEWER_PATH)
            if (!f.isFile || f.length() <= VIEWER_QUEUE_MAX_BYTES) return
            val lines = f.readLines()
            if (lines.size <= VIEWER_QUEUE_KEEP_LINES) return
            val keep = lines.takeLast(VIEWER_QUEUE_KEEP_LINES).joinToString("\n", postfix = "\n")
            writeText(XpPrefs.VIEWER_PATH, keep, append = false)
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
            writeDisabled.set(false)
            runCatching { File(XpPrefs.WRITE_DISABLED_PATH).delete() }
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
            runCatching {
                writeText(
                    XpPrefs.WRITE_DISABLED_PATH,
                    "${System.currentTimeMillis()}\t$what\n",
                    append = false,
                )
            }
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
        if (priority == Log.DEBUG && !isVerbose()) return
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
        // 非详细模式：DEBUG 不进 logcat / 文件，避免前台连切刷屏
        if (priority == Log.DEBUG && !isVerbose()) return
        if (tr != null) log(priority, TAG, msg, tr) else log(priority, TAG, msg)
        appendLogLine(priority, if (tr != null) "$msg (${tr.javaClass.simpleName})" else msg)
    }

    companion object {
        private const val TAG = "QscXp"
        private const val ARM_RECHECK_MS = 60_000L
        private const val PKG_LIST_CACHE_MS = 8_000L
        private const val POLICY_CACHE_MS = 15_000L
        private const val VERBOSE_CACHE_MS = 5_000L
        private const val FG_IDLE_CACHE_MS = 10_000L
        private const val VIEWER_LOG_DEBOUNCE_MS = 2_000L

        /** 进出管理器边沿稳定时间（防抖） */
        private const val MANAGER_STABLE_MS = 3_000L

        /** 普通 App 前台落盘稳定时间（≈800ms，与列表墓碑进入对齐） */
        private const val FG_STABLE_DEBOUNCE_MS = 800L
        private const val LOG_MAX_BYTES = 48_000L
        private const val LOG_KEEP_BYTES = 24_000
        private const val VIEWER_QUEUE_MAX_BYTES = 4_096L
        private const val VIEWER_QUEUE_KEEP_LINES = 16

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
