package com.qsc.battery.xposed

import android.util.Log
import io.github.libxposed.api.XposedInterface
import io.github.libxposed.api.XposedModule
import io.github.libxposed.api.XposedModuleInterface.ModuleLoadedParam
import io.github.libxposed.api.XposedModuleInterface.SystemServerStartingParam
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * LSPosed：仅系统框架；qscd 不可用（arm）时插拔边沿写唤醒文件。
 * 未武装时缓存 arm 检查，避免每次电池回调读 sysfs。
 * 关键日志多路径写入，供伴侣 APP / WebUI「LSP」读取。
 */
class QscXposedModule : XposedModule() {
    private val hookedBattery = AtomicBoolean(false)
    private val writeDisabled = AtomicBoolean(false)
    private val failStreak = AtomicInteger(0)
    private val armCacheAt = AtomicLong(0L)
    private val armCached = AtomicBoolean(false)
    private var lastPlugged: Boolean? = null

    override fun onModuleLoaded(param: ModuleLoadedParam) {
        if (!param.isSystemServer) return
        xpLog(Log.INFO, "ok loaded in system_server api=$apiVersion")
    }

    override fun onSystemServerStarting(param: SystemServerStartingParam) {
        writeAliveOnce()
        hookBatteryService(param.classLoader)
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
                hook(method)
                    .setPriority(XposedInterface.PRIORITY_DEFAULT)
                    .setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept { chain ->
                        val result = chain.proceed()
                        onBatteryProcessed()
                        result
                    }
            }
            xpLog(Log.INFO, "ok BatteryService hooked x${methods.size}")
        }.onFailure {
            hookedBattery.set(false)
            xpLog(Log.ERROR, "hook failed: ${it.message}", it)
        }
    }

    private fun onBatteryProcessed() {
        if (writeDisabled.get()) return
        if (!isArmedCached()) return
        if (File(OFF_PATH).isFile) return

        val plugged = readPluggedQuick()
        val prev = lastPlugged
        lastPlugged = plugged
        if (prev == null || prev == plugged) return

        writeWake(if (plugged) "plug" else "unplug")
    }

    /** 未武装时最多每 60s 再 stat 一次 arm，武装后每次回调都认（边沿要及时）。 */
    private fun isArmedCached(): Boolean {
        val now = System.currentTimeMillis()
        if (armCached.get()) {
            if (File(ARM_PATH).isFile) return true
            armCached.set(false)
            armCacheAt.set(now)
            return false
        }
        if (now - armCacheAt.get() < ARM_RECHECK_MS) return false
        armCacheAt.set(now)
        val on = File(ARM_PATH).isFile
        armCached.set(on)
        return on
    }

    private fun readPluggedQuick(): Boolean {
        for (path in PLUG_ONLINE_PATHS) {
            val v = runCatching { File(path).readText().trim() }.getOrNull() ?: continue
            if (v == "1") return true
        }
        return false
    }

    private fun writeAliveOnce() {
        if (writeDisabled.get()) return
        val ok = writeText(ALIVE_PATH, "${System.currentTimeMillis()}\talive\n", append = false)
        if (ok) {
            failStreak.set(0)
            xpLog(Log.INFO, "ok alive → $ALIVE_PATH")
        } else {
            onWriteFailed("alive")
            xpLog(Log.WARN, "alive write failed → $ALIVE_PATH")
        }
    }

    private fun writeWake(reason: String) {
        if (writeDisabled.get()) return
        val ok = writeText(WAKE_PATH, "${System.currentTimeMillis()}\t$reason\n", append = false)
        if (ok) {
            failStreak.set(0)
            xpLog(Log.INFO, "ok wake $reason → $WAKE_PATH")
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
        if (!wrote) {
            Log.w(TAG, "xp file log write failed all paths: $msg")
        }
    }

    private fun xpLog(priority: Int, msg: String, tr: Throwable? = null) {
        if (tr != null) log(priority, TAG, msg, tr) else log(priority, TAG, msg)
        appendLogLine(priority, if (tr != null) "$msg (${tr.javaClass.simpleName})" else msg)
    }

    companion object {
        private const val TAG = "QscXp"
        private const val ARM_RECHECK_MS = 60_000L
        private const val LOG_MAX_BYTES = 48_000L
        private const val LOG_KEEP_BYTES = 24_000

        const val ARM_PATH = "/data/system/qsc_xp_arm"
        const val WAKE_PATH = "/data/system/qsc_xp_wake"
        const val ALIVE_PATH = "/data/system/qsc_xp_alive"
        const val OFF_PATH = "/data/system/qsc_xp_off"
        const val LOG_PATH = "/data/system/qsc_xp.log"

        /** system_server 可写候选；Magisk 另镜像到模块 data/xp.log */
        private val LOG_PATHS = listOf(
            LOG_PATH,
            "/data/local/tmp/qsc_xp.log",
            "/cache/qsc_xp.log",
        )

        private val PLUG_ONLINE_PATHS = listOf(
            "/sys/class/power_supply/usb/online",
            "/sys/class/power_supply/usb/present",
            "/sys/class/power_supply/pc_port/online",
            "/sys/class/power_supply/ac/online",
            "/sys/class/power_supply/wireless/online",
            "/sys/class/power_supply/dc/online",
        )
    }
}
