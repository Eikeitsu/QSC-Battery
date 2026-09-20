package com.qsc.battery.xposed

import android.util.Log
import io.github.libxposed.api.XposedInterface
import io.github.libxposed.api.XposedModule
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * 可选辅助边沿（默认关；touch want_* 才启用）：
 * - 亮灭屏 → [XpPrefs.SCREEN_PATH]，武装时兼写 wake
 * - Doze 进出 → [XpPrefs.DOZE_PATH]
 * - 白名单广播 → [XpPrefs.BCAST_PATH]
 */
internal object QscXpAssist {
    private val hookedScreen = AtomicBoolean(false)
    private val hookedDoze = AtomicBoolean(false)
    private val hookedBcast = AtomicBoolean(false)
    private val lastScreenOn = AtomicReference<Boolean?>(null)
    private val lastDozeIdle = AtomicReference<Boolean?>(null)
    private val wantCacheAt = AtomicLong(0L)
    private val wantScreen = AtomicBoolean(false)
    private val wantDoze = AtomicBoolean(false)
    private val wantBcast = AtomicBoolean(false)
    private val bcastCacheAt = AtomicLong(0L)
    private val bcastActions = AtomicReference<Set<String>>(emptySet())
    private val armCacheAt = AtomicLong(0L)
    private val armCached = AtomicBoolean(false)

    fun install(mod: XposedModule, loader: ClassLoader, log: (Int, String) -> Unit) {
        hookScreen(mod, loader, log)
        hookDoze(mod, loader, log)
        hookBroadcast(mod, loader, log)
    }

    private fun refreshWants() {
        val now = System.currentTimeMillis()
        if (now - wantCacheAt.get() < 8_000L) return
        wantCacheAt.set(now)
        wantScreen.set(File(XpPrefs.WANT_SCREEN_PATH).isFile)
        wantDoze.set(File(XpPrefs.WANT_DOZE_PATH).isFile)
        wantBcast.set(File(XpPrefs.WANT_BCAST_PATH).isFile)
    }

    private fun xpOff(): Boolean = File(XpPrefs.OFF_PATH).isFile

    private fun isArmed(): Boolean {
        val now = System.currentTimeMillis()
        if (armCached.get()) {
            if (File(XpPrefs.ARM_PATH).isFile) return true
            armCached.set(false)
            armCacheAt.set(now)
            return false
        }
        if (now - armCacheAt.get() < 60_000L) return false
        armCacheAt.set(now)
        val on = File(XpPrefs.ARM_PATH).isFile
        armCached.set(on)
        return on
    }

    private fun writeText(path: String, content: String): Boolean = try {
        val f = File(path)
        val parent = f.parentFile ?: return false
        if (!parent.exists() && !parent.mkdirs()) return false
        FileOutputStream(f, false).use { it.write(content.toByteArray()) }
        true
    } catch (_: Throwable) {
        false
    }

    private fun writeEdge(path: String, value: String, log: (Int, String) -> Unit, tag: String) {
        if (xpOff()) return
        val ok = writeText(path, "${System.currentTimeMillis()}\t$value\n")
        if (ok) {
            log(Log.DEBUG, "assist $tag $value")
        } else {
            log(Log.WARN, "assist $tag write failed")
        }
    }

    private fun maybeWake(reason: String, log: (Int, String) -> Unit) {
        if (xpOff()) return
        if (File(XpPrefs.NO_WAKE_PATH).isFile) return
        if (!isArmed()) return
        if (writeText(XpPrefs.WAKE_PATH, "${System.currentTimeMillis()}\t$reason\n")) {
            log(Log.INFO, "ok assist wake $reason")
        }
    }

    private fun onScreenChange(on: Boolean, log: (Int, String) -> Unit) {
        refreshWants()
        if (!wantScreen.get() || xpOff()) return
        val prev = lastScreenOn.getAndSet(on)
        if (prev != null && prev == on) return
        writeEdge(XpPrefs.SCREEN_PATH, if (on) "on" else "off", log, "screen")
        maybeWake(if (on) "screen_on" else "screen_off", log)
    }

    private fun onDozeChange(idle: Boolean, log: (Int, String) -> Unit) {
        refreshWants()
        if (!wantDoze.get() || xpOff()) return
        val prev = lastDozeIdle.getAndSet(idle)
        if (prev != null && prev == idle) return
        writeEdge(XpPrefs.DOZE_PATH, if (idle) "idle" else "active", log, "doze")
        maybeWake(if (idle) "doze_idle" else "doze_active", log)
    }

    private fun hookScreen(mod: XposedModule, loader: ClassLoader, log: (Int, String) -> Unit) {
        if (!hookedScreen.compareAndSet(false, true)) return
        var n = 0
        n += hookNamed(
            mod, loader, log,
            "com.android.server.power.Notifier",
            listOf("onWakefulnessChangeFinished", "onWakefulnessChangeStarted"),
        ) { chain, _ ->
            val result = chain.proceed()
            val wakefulness = argInt(chain, 0) ?: return@hookNamed result
            // 1=AWAKE；其余视为非亮屏（含 ASLEEP/DREAMING/DOZING）
            onScreenChange(wakefulness == 1, log)
            result
        }
        n += hookNamed(
            mod, loader, log,
            "com.android.server.power.PowerManagerService",
            listOf("setWakefulnessLocked", "setWakefulnessInternal"),
        ) { chain, _ ->
            val result = chain.proceed()
            val wakefulness = argInt(chain, 0) ?: return@hookNamed result
            onScreenChange(wakefulness == 1, log)
            result
        }
        if (n > 0) {
            log(Log.INFO, "ok assist screen hooked sites=$n")
        } else {
            hookedScreen.set(false)
            log(Log.DEBUG, "assist screen: no hook sites")
        }
    }

    private fun hookDoze(mod: XposedModule, loader: ClassLoader, log: (Int, String) -> Unit) {
        if (!hookedDoze.compareAndSet(false, true)) return
        var n = 0
        n += hookNamed(
            mod, loader, log,
            "com.android.server.DeviceIdleController",
            listOf("deepIdleLocked", "becomeActiveLocked", "goIdleLocked", "stepIdleStateLocked"),
        ) { chain, methodName ->
            val result = chain.proceed()
            when (methodName) {
                "becomeActiveLocked" -> onDozeChange(false, log)
                "deepIdleLocked", "goIdleLocked" -> onDozeChange(true, log)
                "stepIdleStateLocked" -> {
                    // 进入 STATE_IDLE(5) / STATE_IDLE_MAINTENANCE(6) 视为 idle
                    val state = argInt(chain, 0)
                    if (state == 5 || state == 6) onDozeChange(true, log)
                }
            }
            result
        }
        if (n > 0) {
            log(Log.INFO, "ok assist doze hooked sites=$n")
        } else {
            hookedDoze.set(false)
            log(Log.DEBUG, "assist doze: no hook sites")
        }
    }

    private fun hookBroadcast(mod: XposedModule, loader: ClassLoader, log: (Int, String) -> Unit) {
        if (!hookedBcast.compareAndSet(false, true)) return
        var n = 0
        val classes = listOf(
            "com.android.server.am.ActivityManagerService",
            "com.android.server.am.BroadcastController",
        )
        val methods = listOf("broadcastIntentLocked", "broadcastIntentWithFeature", "broadcastIntent")
        for (cls in classes) {
            n += hookNamed(mod, loader, log, cls, methods) { chain, _ ->
                val result = chain.proceed()
                refreshWants()
                if (!wantBcast.get() || xpOff()) return@hookNamed result
                val action = intentAction(chain) ?: return@hookNamed result
                if (!isAllowedAction(action)) return@hookNamed result
                writeEdge(XpPrefs.BCAST_PATH, action, log, "bcast")
                maybeWake("bcast:$action", log)
                result
            }
        }
        if (n > 0) {
            log(Log.INFO, "ok assist broadcast hooked sites=$n")
        } else {
            hookedBcast.set(false)
            log(Log.DEBUG, "assist broadcast: no hook sites")
        }
    }

    private fun isAllowedAction(action: String): Boolean {
        val now = System.currentTimeMillis()
        if (now - bcastCacheAt.get() >= 30_000L) {
            bcastCacheAt.set(now)
            val set = linkedSetOf<String>()
            runCatching {
                val f = File(XpPrefs.BCAST_ACTIONS_PATH)
                if (!f.isFile) return@runCatching
                f.readLines().forEach { line ->
                    val a = line.trim()
                    if (a.isNotEmpty() && !a.startsWith("#")) set.add(a)
                }
            }
            // 未配置列表时给一组低噪声默认（仅 want_bcast 开启时生效）
            if (set.isEmpty()) {
                set.add("android.os.action.DEVICE_IDLE_MODE_CHANGED")
                set.add("android.os.action.LIGHT_DEVICE_IDLE_MODE_CHANGED")
                set.add("android.intent.action.SCREEN_ON")
                set.add("android.intent.action.SCREEN_OFF")
                set.add("android.intent.action.ACTION_POWER_CONNECTED")
                set.add("android.intent.action.ACTION_POWER_DISCONNECTED")
            }
            bcastActions.set(set)
        }
        return bcastActions.get().contains(action)
    }

    private fun intentAction(chain: XposedInterface.Chain): String? {
        for (i in 0 until 10) {
            val arg = chainArg(chain, i) ?: continue
            val action = runCatching {
                arg.javaClass.getMethod("getAction").invoke(arg) as? String
            }.getOrNull()
            if (!action.isNullOrBlank()) return action
        }
        return null
    }

    private fun chainArg(chain: XposedInterface.Chain, index: Int): Any? = runCatching {
        val m = chain.javaClass.methods.firstOrNull {
            it.name == "getArg" && it.parameterCount == 1
        }
        m?.invoke(chain, index) ?: run {
            val f = chain.javaClass.methods.firstOrNull {
                (it.name == "getArgs" || it.name == "args") && it.parameterCount == 0
            }
            val arr = f?.invoke(chain) as? Array<*>
            arr?.getOrNull(index)
        }
    }.getOrNull()

    private fun argInt(chain: XposedInterface.Chain, index: Int): Int? = when (val v = chainArg(chain, index)) {
        is Int -> v
        is Number -> v.toInt()
        else -> null
    }

    private fun hookNamed(
        mod: XposedModule,
        loader: ClassLoader,
        log: (Int, String) -> Unit,
        className: String,
        methodNames: List<String>,
        intercept: (XposedInterface.Chain, String) -> Any?,
    ): Int {
        return runCatching {
            val cls = loader.loadClass(className)
            val nameSet = methodNames.toSet()
            val methods = cls.declaredMethods.filter { it.name in nameSet }
            var n = 0
            for (method in methods) {
                runCatching { mod.deoptimize(method) }
                val methodName = method.name
                mod.hook(method)
                    .setPriority(XposedInterface.PRIORITY_DEFAULT)
                    .setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept { chain -> intercept(chain, methodName) }
                n++
            }
            if (n > 0) log(Log.DEBUG, "assist hooked $className x$n")
            n
        }.getOrElse {
            val short = when {
                it is ClassNotFoundException || it.message?.contains("Didn't find class") == true ->
                    "class missing"
                else -> it.message?.take(120) ?: it.javaClass.simpleName
            }
            log(Log.DEBUG, "assist skip $className: $short")
            0
        }
    }
}
