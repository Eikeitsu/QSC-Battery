package com.qsc.battery.data.repo

import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge

class DaemonRepository(private val root: RootBridge) {
    suspend fun status(): String {
        val r = root.exec("sh '${ModulePaths.QSCD_FETCH}' status 2>/dev/null")
        return if (r.ok) r.out else r.err.ifBlank { "unavailable" }
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
        if (!manifestUrl.isNullOrBlank()) {
            parts += "QSCD_MANIFEST_URL='${manifestUrl.replace("'", "")}'"
        }
        if (!pagesBase.isNullOrBlank()) {
            parts += "QSCD_PAGES_BASE='${pagesBase.replace("'", "")}'"
        }
        return if (parts.isEmpty()) "" else parts.joinToString(" ", postfix = " ")
    }
}
