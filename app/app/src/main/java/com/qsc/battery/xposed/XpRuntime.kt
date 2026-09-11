package com.qsc.battery.xposed

import android.content.Context
import java.io.File

/** LSPosed / 框架侧状态探测（现代 API 下模块进程不再自注入）。 */
object XpRuntime {
    private val MANAGER_PACKAGES = listOf(
        "org.lsposed.manager",
        "org.lsposed.manager.lpha",
    )

    fun isManagerInstalled(context: Context): Boolean {
        val pm = context.packageManager
        return MANAGER_PACKAGES.any { pkg ->
            runCatching {
                pm.getPackageInfo(pkg, 0)
                true
            }.getOrDefault(false)
        }
    }

    fun isFrameworkDirPresent(): Boolean =
        File("/data/adb/lspd").exists() || File("/data/adb/modules/zygisk_lsposed").exists()

    /** 界面用：管理器已装或能看到框架目录，即视为「可启用」。 */
    fun isAvailable(context: Context): Boolean =
        isManagerInstalled(context) || isFrameworkDirPresent()
}
