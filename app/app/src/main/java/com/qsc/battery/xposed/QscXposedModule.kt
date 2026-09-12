package com.qsc.battery.xposed

import android.util.Log
import io.github.libxposed.api.XposedInterface
import io.github.libxposed.api.XposedModule
import io.github.libxposed.api.XposedModuleInterface.ModuleLoadedParam
import io.github.libxposed.api.XposedModuleInterface.PackageReadyParam
import io.github.libxposed.api.XposedModuleInterface.SystemServerStartingParam
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * 现代 Xposed API 102 入口。
 *
 * 作用域：系统框架 `android`（见 META-INF/xposed/scope.list）。
 * 仅做供电变化提示落盘，不写任何充电控制节点。
 *
 * 注意：system_server 通常 **不能** 写 `/data/adb/`（SELinux），
 * 心跳必须落到 system 可写路径（如 /data/local/tmp、/data/system）。
 */
class QscXposedModule : XposedModule() {
    private val lastWrite = AtomicLong(0L)
    private val hooked = AtomicBoolean(false)

    override fun onModuleLoaded(param: ModuleLoadedParam) {
        val props = frameworkProperties
        val capSystem = props and XposedInterface.PROP_CAP_SYSTEM != 0L
        val capRemote = props and XposedInterface.PROP_CAP_REMOTE != 0L
        xpLog(
            Log.INFO,
            "onModuleLoaded process=${param.processName} isSystemServer=${param.isSystemServer} " +
                "api=$apiVersion fw=$frameworkName/$frameworkVersion($frameworkVersionCode) " +
                "PROP_CAP_SYSTEM=$capSystem PROP_CAP_REMOTE=$capRemote props=0x${props.toString(16)}",
        )
        if (!capSystem && param.isSystemServer) {
            xpLog(Log.WARN, "framework reports no PROP_CAP_SYSTEM but loaded in system_server")
        }
        if (param.isSystemServer) {
            writeHeartbeat("module_loaded_system_server")
        } else {
            writeHeartbeat("module_loaded_${param.processName}")
        }
    }

    override fun onSystemServerStarting(param: SystemServerStartingParam) {
        xpLog(Log.INFO, "onSystemServerStarting classLoader=${param.classLoader}")
        writeHeartbeat("system_server_starting")
        hookBatteryService(param.classLoader)
    }

    override fun onPackageReady(param: PackageReadyParam) {
        // 系统服务主路径是 onSystemServerStarting；这里只记日志，避免重复 hook
        xpLog(
            Log.DEBUG,
            "onPackageReady pkg=${param.packageName} isFirst=${param.isFirstPackage}",
        )
    }

    private fun hookBatteryService(loader: ClassLoader) {
        if (!hooked.compareAndSet(false, true)) {
            xpLog(Log.INFO, "BatteryService hook already installed")
            return
        }
        runCatching {
            val cls = loader.loadClass("com.android.server.BatteryService")
            val methods = cls.declaredMethods.filter { it.name == "processValuesLocked" }
            if (methods.isEmpty()) {
                xpLog(
                    Log.WARN,
                    "BatteryService.processValuesLocked not found; " +
                        "methods=${cls.declaredMethods.map { it.name }.distinct().sorted()}",
                )
                // 仍算已注入：启动心跳已写入
                writeHeartbeat("hook_miss_processValuesLocked")
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
                xpLog(Log.INFO, "hooked ${method.declaringClass.name}.${method.name}${method.parameterCount}")
            }
            writeHeartbeat("hooked_processValuesLocked_x${methods.size}")
        }.onFailure {
            hooked.set(false)
            xpLog(Log.ERROR, "hook BatteryService failed: ${it.message}", it)
            writeHeartbeat("hook_failed")
        }
    }

    private fun onBatteryProcessed() {
        if (!powerEventsEnabled()) {
            xpLog(Log.DEBUG, "power events disabled by flag $XP_OFF_FLAG")
            return
        }
        val now = System.currentTimeMillis()
        if (now - lastWrite.get() < 15_000L) return
        lastWrite.set(now)
        writeWakeHint("battery_process")
        writeHeartbeat("battery_process")
    }

    private fun powerEventsEnabled(): Boolean = !File(XP_OFF_FLAG).exists()

    private fun writeHeartbeat(reason: String) {
        val line = "${System.currentTimeMillis()}\t$reason\n"
        var ok = 0
        for (path in HEARTBEAT_PATHS) {
            val result = writeTextFile(path, line, append = false)
            if (result == null) {
                ok++
                xpLog(Log.INFO, "heartbeat ok → $path ($reason)")
            } else {
                xpLog(Log.WARN, "heartbeat fail → $path: $result")
            }
        }
        if (ok == 0) {
            xpLog(Log.ERROR, "heartbeat wrote nowhere; check SELinux / path permissions ($reason)")
        }
    }

    private fun writeWakeHint(action: String) {
        val line = "${System.currentTimeMillis()}\t$action\n"
        for (path in WAKE_HINT_PATHS) {
            val err = writeTextFile(path, line, append = true, trimBytes = 64_000)
            if (err == null) {
                xpLog(Log.DEBUG, "wake hint → $path ($action)")
                return
            }
            xpLog(Log.DEBUG, "wake hint skip $path: $err")
        }
    }

    /** @return null on success, error message on failure */
    private fun writeTextFile(
        path: String,
        content: String,
        append: Boolean,
        trimBytes: Long = 0,
    ): String? {
        return try {
            val f = File(path)
            val parent = f.parentFile ?: return "no parent"
            if (!parent.exists() && !parent.mkdirs()) {
                return "mkdirs failed: ${parent.absolutePath}"
            }
            if (append) {
                f.appendText(content)
                if (trimBytes > 0 && f.length() > trimBytes) {
                    f.writeText(content)
                }
            } else {
                f.writeText(content)
            }
            // 尽量让 APP/shell 可读
            runCatching {
                f.setReadable(true, false)
                f.setWritable(true, false)
            }
            null
        } catch (t: Throwable) {
            t.javaClass.simpleName + ": " + (t.message ?: "unknown")
        }
    }

    private fun xpLog(priority: Int, msg: String, tr: Throwable? = null) {
        // LSPosed 日志 + logcat，便于 adb logcat -s QscXp 排查
        if (tr != null) {
            log(priority, TAG, msg, tr)
            Log.println(priority, TAG, msg + "\n" + Log.getStackTraceString(tr))
        } else {
            log(priority, TAG, msg)
            Log.println(priority, TAG, msg)
        }
    }

    companion object {
        private const val TAG = "QscXp"
        private const val XP_OFF_FLAG = "/data/local/tmp/qsc_xp_power_events_off"

        /** system_server 可写优先；/data/adb 常被 SELinux 拒绝，仅作兜底 */
        val HEARTBEAT_PATHS = listOf(
            "/data/local/tmp/qsc_xp_heartbeat",
            "/data/system/qsc_xp_heartbeat",
            "/cache/qsc_xp_heartbeat",
            "/data/adb/qsc/xp_heartbeat",
        )

        private val WAKE_HINT_PATHS = listOf(
            "/data/local/tmp/qsc_xp_power_event",
            "/data/system/qsc_xp_power_event",
            "/data/adb/qsc/xp_power_event",
        )
    }
}
