package com.qsc.battery.xposed

import android.content.SharedPreferences
import com.qsc.battery.core.RootBridge
import io.github.libxposed.service.XposedService
import io.github.libxposed.service.XposedServiceHelper
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume

/**
 * 对齐 HyperCeiler ScopeManager / libxposed example：
 * Application 注册 listener，经 XposedProvider 接收 binder。
 */
object XpServiceHolder : XposedServiceHelper.OnServiceListener {
    private val serviceRef = AtomicReference<XposedService?>(null)
    private val waiters = CopyOnWriteArrayList<CompletableDeferred<XposedService>>()

    data class FrameworkInfo(
        val apiVersion: Int,
        val name: String,
        val version: String,
        val versionCode: Long,
    )

    val service: XposedService? get() = serviceRef.get()

    fun install() {
        XposedServiceHelper.registerListener(this)
    }

    override fun onServiceBind(service: XposedService) {
        serviceRef.set(service)
        waiters.toList().forEach { d ->
            d.complete(service)
            waiters.remove(d)
        }
    }

    override fun onServiceDied(service: XposedService) {
        serviceRef.compareAndSet(service, null)
    }

    suspend fun awaitService(timeoutMs: Long = 2000L): XposedService? {
        serviceRef.get()?.let { return it }
        val d = CompletableDeferred<XposedService>()
        waiters.add(d)
        serviceRef.get()?.let {
            waiters.remove(d)
            return it
        }
        return try {
            withTimeoutOrNull(timeoutMs) { d.await() }
        } finally {
            waiters.remove(d)
        }
    }

    fun frameworkInfo(svc: XposedService = service ?: return null): FrameworkInfo? =
        runCatching {
            FrameworkInfo(
                apiVersion = svc.apiVersion,
                name = svc.frameworkName.orEmpty(),
                version = svc.frameworkVersion.orEmpty(),
                versionCode = runCatching { svc.frameworkVersionCode.toLong() }.getOrDefault(0L),
            )
        }.getOrNull()

    fun scopeList(svc: XposedService = service ?: return emptyList()): List<String> =
        runCatching { svc.scope?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty() }
            .getOrDefault(emptyList())

    fun runningTargetNames(svc: XposedService = service ?: return emptyList()): List<String> {
        return runCatching {
            if (svc.apiVersion < 102) return emptyList()
            svc.runningTargets.mapNotNull { t ->
                runCatching { t.processName }.getOrNull()?.takeIf { it.isNotBlank() }
            }
        }.getOrDefault(emptyList())
    }

    fun remotePrefs(svc: XposedService? = service): SharedPreferences? =
        runCatching { svc?.getRemotePreferences(XpPrefs.REMOTE_GROUP) }.getOrNull()

    /**
     * 请求系统框架作用域（LSPosed UI 确认为 `system`）。
     * @return 结果说明；null 表示服务不可用
     */
    suspend fun requestSystemScope(): String? {
        val svc = awaitService(2000L) ?: return null
        return suspendCancellableCoroutine { cont ->
            val listener = object : XposedService.OnScopeEventListener {
                override fun onScopeRequestApproved(approved: List<String>) {
                    if (!cont.isActive) return
                    val ok = approved.any { it.trim().lowercase() in XpPrefs.SYSTEM_SCOPE_PKGS }
                    cont.resume(
                        if (ok) "已批准系统框架作用域"
                        else "请求完成，返回：${approved.joinToString().ifBlank { "(空)" }}",
                    )
                }

                override fun onScopeRequestFailed(message: String) {
                    if (cont.isActive) cont.resume("请求失败：$message")
                }
            }
            try {
                svc.requestScope(listOf("system"), listener)
            } catch (e: Throwable) {
                if (cont.isActive) cont.resume("请求异常：${e.message}")
            }
        }
    }

    /** 写 RemotePrefs，并用 Root 同步到 /data/system 供 Magisk 与 XP 读取。 */
    suspend fun setWakeEnabled(enabled: Boolean, root: RootBridge): Boolean = withContext(Dispatchers.IO) {
        remotePrefs()?.edit()?.putBoolean(XpPrefs.KEY_WAKE_ENABLED, enabled)?.apply()
        if (enabled) root.rm(XpPrefs.NO_WAKE_PATH) else root.touch(XpPrefs.NO_WAKE_PATH)
        true
    }

    suspend fun setXpOff(off: Boolean, root: RootBridge): Boolean = withContext(Dispatchers.IO) {
        remotePrefs()?.edit()?.putBoolean(XpPrefs.KEY_XP_OFF, off)?.apply()
        if (off) root.touch(XpPrefs.OFF_PATH) else root.rm(XpPrefs.OFF_PATH)
        true
    }

    suspend fun setVerboseLog(verbose: Boolean, root: RootBridge): Boolean = withContext(Dispatchers.IO) {
        remotePrefs()?.edit()?.putBoolean(XpPrefs.KEY_VERBOSE_LOG, verbose)?.apply()
        if (verbose) root.touch(XpPrefs.VERBOSE_PATH) else root.rm(XpPrefs.VERBOSE_PATH)
        true
    }

    suspend fun readToggleState(root: RootBridge): ToggleState = withContext(Dispatchers.IO) {
        val prefs = remotePrefs()
        val wake = prefs?.getBoolean(XpPrefs.KEY_WAKE_ENABLED, true)
            ?: !root.exists(XpPrefs.NO_WAKE_PATH)
        val off = prefs?.getBoolean(XpPrefs.KEY_XP_OFF, false)
            ?: root.exists(XpPrefs.OFF_PATH)
        val verbose = prefs?.getBoolean(XpPrefs.KEY_VERBOSE_LOG, false)
            ?: root.exists(XpPrefs.VERBOSE_PATH)
        ToggleState(wakeEnabled = wake, xpOff = off, verboseLog = verbose)
    }

    data class ToggleState(
        val wakeEnabled: Boolean,
        val xpOff: Boolean,
        val verboseLog: Boolean,
    )
}
