package com.qsc.battery.data.repo

import com.qsc.battery.core.GithubCdn
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge

class DaemonRepository(private val root: RootBridge) {
    suspend fun status(): String {
        val r = root.exec("sh '${ModulePaths.QSCD_FETCH}' status 2>/dev/null")
        return if (r.ok) r.out else r.err.ifBlank { "unavailable" }
    }

    suspend fun preferredImpl(): String {
        val used = root.exec("cat '${ModulePaths.DATADIR}/native_impl_used' 2>/dev/null")
            .out.trim().lowercase()
        if (used == "rust" || used == "c") return used
        val conf = root.exec(
            "sed -n 's/^native_impl=//p' '${ModulePaths.CONF}' 2>/dev/null | head -1",
        ).out.trim().lowercase()
        return if (conf == "c") "c" else "rust"
    }

    suspend fun check(
        impl: String? = null,
        manifestUrl: String? = null,
        pagesBase: String? = null,
    ): String {
        val env = envPrefix(manifestUrl, pagesBase)
        val arg = impl?.takeIf { it.isNotBlank() }?.let { " '$it'" } ?: ""
        val r = root.exec("${env}sh '${ModulePaths.QSCD_FETCH}' check$arg 2>/dev/null")
        return (r.out + "\n" + r.err).trim()
    }

    suspend fun install(
        impl: String,
        manifestUrl: String? = null,
        pagesBase: String? = null,
    ): String {
        val env = envPrefix(manifestUrl, pagesBase)
        val r = root.exec("${env}sh '${ModulePaths.QSCD_FETCH}' install '$impl' 2>/dev/null")
        return (r.out + "\n" + r.err).trim()
    }

    suspend fun use(impl: String): String {
        val r = root.exec("sh '${ModulePaths.QSCD_FETCH}' use '$impl' 2>/dev/null")
        return (r.out + "\n" + r.err).trim()
    }

    suspend fun remove(): String {
        val r = root.exec("sh '${ModulePaths.QSCD_FETCH}' remove 2>/dev/null")
        return (r.out + "\n" + r.err).trim()
    }

    suspend fun hasBinary(): Boolean = root.exists(ModulePaths.QSCD)

    private fun envPrefix(manifestUrl: String?, pagesBase: String?): String {
        val parts = mutableListOf<String>()
        val manifest = manifestUrl?.takeIf { it.isNotBlank() }?.let(GithubCdn::preferReachable)
        val pages = GithubCdn.pagesRootForDaemon(pagesBase)
        if (!manifest.isNullOrBlank()) {
            parts += "QSCD_MANIFEST_URL='${manifest.replace("'", "")}'"
        }
        if (!pages.isNullOrBlank()) {
            parts += "QSCD_PAGES_BASE='${pages.replace("'", "")}'"
        }
        return if (parts.isEmpty()) "" else parts.joinToString(" ", postfix = " ")
    }
}
