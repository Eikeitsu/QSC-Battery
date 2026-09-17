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
        preferCdn: Boolean = false,
    ): String {
        val env = envPrefix(manifestUrl, pagesBase, preferCdn = preferCdn)
        val arg = impl?.takeIf { it.isNotBlank() }?.let { " '$it'" } ?: ""
        val r = root.exec("${env}sh '${ModulePaths.QSCD_FETCH}' check$arg 2>/dev/null")
        return (r.out + "\n" + r.err).trim()
    }

    suspend fun install(
        impl: String,
        manifestUrl: String? = null,
        pagesBase: String? = null,
        localBin: String? = null,
        preferCdn: Boolean = false,
    ): String {
        val env = envPrefix(manifestUrl, pagesBase, localBin, preferCdn)
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

    private fun envPrefix(
        manifestUrl: String?,
        pagesBase: String?,
        localBin: String? = null,
        preferCdn: Boolean = false,
    ): String {
        val parts = mutableListOf<String>()
        // 本地路径（materialize）原样；仅 HTTP 按 CDN 开关改写
        val manifest = manifestUrl?.takeIf { it.isNotBlank() }?.let { u ->
            if (u.startsWith("http")) GithubCdn.toChannelAssetUrl(u, preferCdn) else u
        }
        val pages = GithubCdn.pagesRootForDaemon(pagesBase, preferCdn)
        if (!manifest.isNullOrBlank()) {
            parts += "QSCD_MANIFEST_URL='${manifest.replace("'", "")}'"
        }
        if (!pages.isNullOrBlank()) {
            parts += "QSCD_PAGES_BASE='${pages.replace("'", "")}'"
        }
        if (!localBin.isNullOrBlank()) {
            parts += "QSCD_LOCAL_BIN='${localBin.replace("'", "")}'"
        }
        return if (parts.isEmpty()) "" else parts.joinToString(" ", postfix = " ")
    }
}
