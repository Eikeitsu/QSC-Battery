package com.qsc.battery.xposed

import de.robv.android.xposed.IXposedHookLoadPackage
import de.robv.android.xposed.IXposedHookZygoteInit
import de.robv.android.xposed.XC_MethodHook
import de.robv.android.xposed.XSharedPreferences
import de.robv.android.xposed.XposedBridge
import de.robv.android.xposed.XposedHelpers
import de.robv.android.xposed.callbacks.XC_LoadPackage
import java.io.File
import java.util.concurrent.atomic.AtomicLong

/**
 * LSPosed / Xposed 入口。
 * 仅做供电变化提示落盘，不写任何充电控制节点。
 */
class XposedInit : IXposedHookZygoteInit, IXposedHookLoadPackage {
    override fun initZygote(startupParam: IXposedHookZygoteInit.StartupParam) = Unit

    override fun handleLoadPackage(lpparam: XC_LoadPackage.LoadPackageParam) {
        when (lpparam.packageName) {
            "com.qsc.battery", "com.qsc.battery.debug" -> markAppHooked(lpparam)
            "android" -> hookBatteryService(lpparam)
        }
    }

    private fun markAppHooked(lpparam: XC_LoadPackage.LoadPackageParam) {
        runCatching {
            val clazz = XposedHelpers.findClass(
                "com.qsc.battery.xposed.XpRuntime",
                lpparam.classLoader,
            )
            XposedHelpers.setStaticBooleanField(clazz, "isHooked", true)
        }
    }

    private fun hookBatteryService(lpparam: XC_LoadPackage.LoadPackageParam) {
        val lastWrite = AtomicLong(0L)
        val cls = runCatching {
            XposedHelpers.findClass("com.android.server.BatteryService", lpparam.classLoader)
        }.getOrNull() ?: return

        XposedBridge.hookAllMethods(
            cls,
            "processValuesLocked",
            object : XC_MethodHook() {
                override fun afterHookedMethod(param: MethodHookParam) {
                    if (!powerEventsEnabled()) return
                    val now = System.currentTimeMillis()
                    // 节流：避免每次电量跳动都写盘；模块轮询侧可读最新时间戳
                    if (now - lastWrite.get() < 15_000L) return
                    lastWrite.set(now)
                    writeWakeHint("battery_process")
                }
            },
        )
    }

    private fun powerEventsEnabled(): Boolean {
        return runCatching {
            fun read(pkg: String): Boolean? {
                val prefs = XSharedPreferences(pkg, "qsc_xp")
                prefs.reload()
                return if (prefs.file.canRead()) prefs.getBoolean("xp_power_events", true) else null
            }
            read("com.qsc.battery") ?: read("com.qsc.battery.debug") ?: true
        }.getOrDefault(true)
    }

    private fun writeWakeHint(action: String) {
        val line = "${System.currentTimeMillis()}\t$action\n"
        val targets = listOf(
            "/data/adb/qsc/xp_power_event",
            "/data/local/tmp/qsc_xp_power_event",
        )
        for (path in targets) {
            runCatching {
                val f = File(path)
                f.parentFile?.mkdirs()
                f.appendText(line)
                if (f.length() > 64_000) f.writeText(line)
                return
            }
        }
    }
}
