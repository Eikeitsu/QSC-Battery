package com.qsc.battery.xposed

import android.util.Log
import io.github.libxposed.api.XposedInterface
import io.github.libxposed.api.XposedModule
import io.github.libxposed.api.XposedModuleInterface.PackageReadyParam
import io.github.libxposed.api.XposedModuleInterface.SystemServerStartingParam
import java.io.File
import java.util.concurrent.atomic.AtomicLong

/**
 * 现代 Xposed API 102 入口。
 * 仅做供电变化提示落盘，不写任何充电控制节点。
 */
class QscXposedModule : XposedModule() {
    private val lastWrite = AtomicLong(0L)

    override fun onSystemServerStarting(param: SystemServerStartingParam) {
        writeHeartbeat("system_server_starting")
        hookBatteryService(param.classLoader)
    }

    override fun onPackageReady(param: PackageReadyParam) {
        // 系统服务已在 onSystemServerStarting 处理
    }

    private fun hookBatteryService(loader: ClassLoader) {
        runCatching {
            val cls = loader.loadClass("com.android.server.BatteryService")
            val methods = cls.declaredMethods.filter { it.name == "processValuesLocked" }
            if (methods.isEmpty()) {
                log(Log.WARN, TAG, "BatteryService.processValuesLocked not found")
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
            writeHeartbeat("hooked")
            log(Log.INFO, TAG, "hooked BatteryService.processValuesLocked x${methods.size}")
        }.onFailure {
            log(Log.ERROR, TAG, "hook BatteryService failed", it)
        }
    }

    private fun onBatteryProcessed() {
        if (!powerEventsEnabled()) return
        val now = System.currentTimeMillis()
        if (now - lastWrite.get() < 15_000L) return
        lastWrite.set(now)
        writeWakeHint("battery_process")
        writeHeartbeat("battery_process")
    }

    private fun powerEventsEnabled(): Boolean = !File(XP_OFF_FLAG).exists()

    private fun writeHeartbeat(reason: String) {
        val line = "${System.currentTimeMillis()}\t$reason\n"
        runCatching {
            val f = File(HEARTBEAT)
            f.parentFile?.mkdirs()
            f.writeText(line)
        }
    }

    private fun writeWakeHint(action: String) {
        val line = "${System.currentTimeMillis()}\t$action\n"
        for (path in TARGETS) {
            runCatching {
                val f = File(path)
                f.parentFile?.mkdirs()
                f.appendText(line)
                if (f.length() > 64_000) f.writeText(line)
                return
            }
        }
    }

    companion object {
        private const val TAG = "QscXp"
        private const val XP_OFF_FLAG = "/data/adb/qsc/xp_power_events_off"
        private const val HEARTBEAT = "/data/adb/qsc/xp_heartbeat"
        private val TARGETS = listOf(
            "/data/adb/qsc/xp_power_event",
            "/data/local/tmp/qsc_xp_power_event",
        )
    }
}
