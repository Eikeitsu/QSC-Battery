package com.qsc.battery.update

import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.data.repo.DaemonRepository
import com.qsc.battery.data.repo.ModuleInstallRepository
import com.qsc.battery.data.repo.SettingsRepository
import com.qsc.battery.data.repo.StatusRepository
import com.qsc.battery.data.repo.UpdateRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class UpdateTarget { Module, App, Daemon }

sealed interface UpdateWork {
    data object Idle : UpdateWork
    data object Checking : UpdateWork
    data class Downloading(
        val target: UpdateTarget,
        val fraction: Float?,
        val label: String,
    ) : UpdateWork

    data class Installing(val target: UpdateTarget, val label: String) : UpdateWork
}

/**
 * 更新页会话：检查/下载不绑定 Composable 生命周期，离开页面后仍可观察进度。
 */
class UpdatesSession(
    private val updates: UpdateRepository,
    private val modules: ModuleInstallRepository,
    private val daemon: DaemonRepository,
    private val status: StatusRepository,
    private val settings: SettingsRepository,
    private val notifier: UpdateDownloadNotifier,
    private val scope: CoroutineScope,
) {
    private val _channel = MutableStateFlow(UpdateChannel.Stable)
    val channel: StateFlow<UpdateChannel> = _channel.asStateFlow()

    private val _preferCdn = MutableStateFlow(true)
    val preferCdn: StateFlow<Boolean> = _preferCdn.asStateFlow()

    private val _result = MutableStateFlow<UpdateCheckResult?>(null)
    val result: StateFlow<UpdateCheckResult?> = _result.asStateFlow()

    private val _work = MutableStateFlow<UpdateWork>(UpdateWork.Idle)
    val work: StateFlow<UpdateWork> = _work.asStateFlow()

    private val _actionError = MutableStateFlow<String?>(null)
    val actionError: StateFlow<String?> = _actionError.asStateFlow()

    private val _actionErrorTarget = MutableStateFlow<UpdateTarget?>(null)
    val actionErrorTarget: StateFlow<UpdateTarget?> = _actionErrorTarget.asStateFlow()

    private val _snackbar = MutableStateFlow<String?>(null)
    val snackbar: StateFlow<String?> = _snackbar.asStateFlow()

    private val mutex = Mutex()
    private var checkJob: Job? = null
    private var actionJob: Job? = null
    private var booted = false

    fun consumeSnackbar(): String? {
        val m = _snackbar.value
        _snackbar.value = null
        return m
    }

    fun clearActionError() {
        _actionError.value = null
        _actionErrorTarget.value = null
    }

    /** 首次进入：读设置并检查。 */
    fun ensureBootstrapped() {
        if (booted) return
        booted = true
        scope.launch {
            _channel.value = settings.updateChannel()
            _preferCdn.value = settings.preferCdn()
            scheduleCheck(debounceMs = 0L)
        }
    }

    fun setChannel(next: UpdateChannel) {
        if (next == _channel.value) return
        _channel.value = next
        scope.launch {
            settings.setUpdateChannel(next)
            scheduleCheck(debounceMs = 300L)
        }
    }

    fun setPreferCdn(on: Boolean) {
        if (on == _preferCdn.value) return
        _preferCdn.value = on
        scope.launch {
            settings.setPreferCdn(on)
            if (_channel.value == UpdateChannel.Ci) {
                scheduleCheck(debounceMs = 200L)
            }
        }
    }

    fun refresh() {
        scheduleCheck(debounceMs = 0L)
    }

    fun updateTarget(target: UpdateTarget) {
        if (_work.value !is UpdateWork.Idle) return
        actionJob?.cancel()
        actionJob = scope.launch {
            mutex.withLock {
                runCatching { performUpdate(target) }
                    .onFailure { fail(it.message ?: "失败", target) }
            }
        }
    }

    /** 模块 → 守护 → APP；任一项失败即停止。模块请走控制台页，此处跳过。 */
    fun updateAll() {
        if (_work.value !is UpdateWork.Idle) return
        val r = _result.value ?: return
        val order = buildList {
            if (canUpdateDaemon(r)) add(UpdateTarget.Daemon)
            if (canUpdateApp(r)) add(UpdateTarget.App)
        }
        if (order.isEmpty()) return
        actionJob?.cancel()
        actionJob = scope.launch {
            mutex.withLock {
                for (t in order) {
                    val ok = runCatching { performUpdate(t) }.getOrElse {
                        fail(it.message ?: "失败", t)
                        return@withLock
                    }
                    if (!ok) return@withLock
                }
            }
        }
    }

    private fun scheduleCheck(debounceMs: Long) {
        checkJob?.cancel()
        checkJob = scope.launch {
            if (debounceMs > 0) delay(debounceMs)
            if (_work.value !is UpdateWork.Idle && _work.value !is UpdateWork.Checking) {
                // 下载/安装中不打断；稍后由成功回调再 refresh
                return@launch
            }
            mutex.withLock {
                if (_work.value is UpdateWork.Downloading || _work.value is UpdateWork.Installing) {
                    return@withLock
                }
                _work.value = UpdateWork.Checking
                _actionError.value = null
                _actionErrorTarget.value = null
                val ch = _channel.value
                val cdn = _preferCdn.value
                val r = runCatching { updates.check(status, ch, cdn) }
                    .onFailure {
                        _actionError.value = it.message ?: "检查失败"
                        _actionErrorTarget.value = null
                        _snackbar.value = it.message ?: "检查失败"
                    }
                    .getOrNull()
                if (r != null) {
                    _result.value = r
                }
                _work.value = UpdateWork.Idle
            }
        }
    }

    private suspend fun performUpdate(target: UpdateTarget): Boolean {
        val r = _result.value ?: return false
        _actionError.value = null
        _actionErrorTarget.value = null
        return when (target) {
            UpdateTarget.Module -> {
                // 模块安装改由 ModuleInstallConsoleScreen 展示命令行过程
                false
            }
            UpdateTarget.App -> {
                val url = r.appRemote?.apkUrl ?: return false
                if (!canUpdateApp(r)) return false
                downloadAnd(
                    target = UpdateTarget.App,
                    url = url,
                    fileName = "QSC-Battery.apk",
                    downloadTitle = "下载 APP",
                ) { file ->
                    _work.value = UpdateWork.Installing(UpdateTarget.App, "打开安装界面…")
                    notifier.progress("安装 APP", "请完成系统安装", null)
                    modules.promptInstallApk(file)
                    notifier.success("APP 安装", "已打开系统安装界面")
                    _snackbar.value = "请完成系统安装后返回并刷新"
                    // 安装器可能还要读文件：后台延迟静默删，不提示
                    scope.launch(Dispatchers.IO) {
                        delay(180_000L)
                        updates.deleteCacheUpdateFile("QSC-Battery.apk")
                    }
                }
                true
            }
            UpdateTarget.Daemon -> {
                if (!canUpdateDaemon(r)) return false
                val (manifest, pages) = updates.channelDaemonUrls(_channel.value)
                val impl = daemon.preferredImpl()
                val remoteManifest = r.daemonRemote?.manifestUrl ?: manifest
                val preferCdn = _preferCdn.value
                _work.value = UpdateWork.Downloading(UpdateTarget.Daemon, null, "正在下载守护…")
                notifier.start("安装守护", "正在下载…")
                val prep = runCatching {
                    updates.prepareChannelDaemonInstall(
                        manifestUrl = remoteManifest,
                        impl = impl,
                        preferCdn = preferCdn,
                    ) { read, total ->
                        val f = if (total != null && total > 0L) {
                            (read.toDouble() / total.toDouble()).toFloat().coerceIn(0f, 1f)
                        } else {
                            null
                        }
                        val label = if (f != null) {
                            "下载守护 ${(f * 100).toInt()}%"
                        } else {
                            "正在下载守护…"
                        }
                        scope.launch(Dispatchers.Main.immediate) {
                            _work.value = UpdateWork.Downloading(UpdateTarget.Daemon, f, label)
                        }
                        notifier.progress("安装守护", label, f)
                    }
                }.getOrElse {
                    fail(it.message ?: "守护下载失败", UpdateTarget.Daemon)
                    return false
                }
                try {
                    _work.value = UpdateWork.Installing(UpdateTarget.Daemon, "正在安装守护…")
                    notifier.progress("安装守护", "正在安装…", null)
                    var msg = daemon.install(
                        impl = impl,
                        manifestUrl = prep.localManifest,
                        pagesBase = r.daemonRemote?.baseUrl ?: pages,
                        localBin = prep.localBin,
                    )
                    // 旧版 qscd_fetch 不认本地清单/二进制时，回退到 CDN HTTP
                    if (!msg.contains("ok=1") && prep.localBin != null) {
                        msg = daemon.install(
                            impl = impl,
                            manifestUrl = remoteManifest,
                            pagesBase = r.daemonRemote?.baseUrl ?: pages,
                        )
                    }
                    if (msg.contains("ok=1")) {
                        notifier.success("守护已更新", "安装完成")
                        _snackbar.value = "守护已更新"
                        _work.value = UpdateWork.Idle
                        scheduleCheck(0L)
                        true
                    } else {
                        fail(humanizeDaemonError(msg), UpdateTarget.Daemon)
                        false
                    }
                } finally {
                    // 后台静默清理临时文件，成败不提示
                    scope.launch(Dispatchers.IO) {
                        runCatching { updates.cleanupChannelDaemonBin() }
                    }
                }
            }
        }
    }

    private suspend fun downloadAnd(
        target: UpdateTarget,
        url: String,
        fileName: String,
        downloadTitle: String,
        after: suspend (java.io.File) -> Unit,
    ) {
        _work.value = UpdateWork.Downloading(target, null, "$downloadTitle…")
        notifier.start(downloadTitle, "准备中…")
        val file = updates.downloadToCache(url, fileName) { read, total ->
            val f = if (total != null && total > 0L) {
                (read.toDouble() / total.toDouble()).toFloat().coerceIn(0f, 1f)
            } else {
                null
            }
            val label = if (f != null) "$downloadTitle ${(f * 100).toInt()}%" else "$downloadTitle…"
            // download callback is on IO; hop to Main for Compose collectors
            scope.launch(Dispatchers.Main.immediate) {
                _work.value = UpdateWork.Downloading(target, f, label)
            }
            notifier.progress(downloadTitle, label, f)
        }
        after(file)
        _work.value = UpdateWork.Idle
    }

    private fun fail(message: String, target: UpdateTarget) {
        _actionError.value = message
        _actionErrorTarget.value = target
        _snackbar.value = message
        _work.value = UpdateWork.Idle
        notifier.failure("更新失败", message.take(80))
    }

    companion object {
        fun canUpdateModule(r: UpdateCheckResult): Boolean =
            !r.moduleRemote?.zipUrl.isNullOrBlank() &&
                (r.moduleHasUpdate || r.moduleCanSwitch || r.moduleLocal == null)

        fun isModuleSwitch(r: UpdateCheckResult): Boolean =
            r.moduleCanSwitch && !r.moduleHasUpdate && r.moduleLocal != null

        fun canUpdateApp(r: UpdateCheckResult): Boolean =
            (r.appHasUpdate || r.appCanSwitch) && !r.appRemote?.apkUrl.isNullOrBlank()

        fun isAppSwitch(r: UpdateCheckResult): Boolean =
            r.appCanSwitch && !r.appHasUpdate

        fun canUpdateDaemon(r: UpdateCheckResult): Boolean =
            (r.daemonHasUpdate || r.daemonCanSwitch) && r.daemonRemote?.manifestUrl != null

        fun isDaemonSwitch(r: UpdateCheckResult): Boolean =
            r.daemonCanSwitch && !r.daemonHasUpdate

        fun updatableCount(r: UpdateCheckResult): Int {
            var n = 0
            if (canUpdateModule(r)) n++
            if (canUpdateApp(r)) n++
            if (canUpdateDaemon(r)) n++
            return n
        }

        fun humanizeDaemonError(raw: String): String {
            val code = Regex("""(?m)^error=(\S+)""")
                .find(raw)
                ?.groupValues
                ?.getOrNull(1)
                ?.trim()
                .orEmpty()
            return when (code) {
                "unsupported_arch" -> "本机架构没有可用的守护文件"
                "manifest_download_failed" -> "取不到守护清单，请检查网络后重试"
                "manifest_invalid_version" -> "远端版本号格式无效，请换通道或稍后重试"
                "manifest_no_entry" -> "清单里没有本机架构的文件"
                "download_failed" -> "守护下载失败，请检查网络后重试"
                "no_sha256_tool" -> "系统缺少校验工具，已放弃安装"
                "sha256_mismatch" -> "文件校验失败，已丢弃"
                "probe_failed" -> "已下载但本机自检未通过，已回滚"
                "bad_impl" -> "参数错误"
                else -> if (code.isNotBlank()) {
                    "守护安装失败（$code）"
                } else {
                    raw.lineSequence()
                        .map { it.trim() }
                        .firstOrNull { it.isNotBlank() && !it.startsWith("ok=") }
                        ?.take(120)
                        ?: "守护安装失败"
                }
            }
        }
    }
}
