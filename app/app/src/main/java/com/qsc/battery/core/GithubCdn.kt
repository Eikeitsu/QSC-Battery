package com.qsc.battery.core

/**
 * Device-side curl/wget often cannot reach raw.githubusercontent.com (esp. CN).
 * Prefer jsDelivr for shell installs; APP OkHttp checks can still use either.
 */
object GithubCdn {
    private val RAW = Regex(
        """^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.*)$""",
    )

    /** Rewrite raw.githubusercontent.com → cdn.jsdelivr.net/gh/...@branch/... */
    fun preferReachable(url: String): String {
        val m = RAW.matchEntire(url.trim()) ?: return url
        val (owner, repo, branch, path) = m.destructured
        return "https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$path"
    }

    /**
     * qscd_fetch uses `$QSCD_PAGES_BASE/qscd/<name>` as binary fallback.
     * Manifest `baseUrl` points at the `qscd` folder — strip that suffix for PAGES_BASE.
     */
    fun pagesRootForDaemon(baseOrRoot: String?): String? {
        if (baseOrRoot.isNullOrBlank()) return null
        val rewritten = preferReachable(baseOrRoot.trim().trimEnd('/'))
        return rewritten.removeSuffix("/qscd").ifBlank { rewritten }
    }
}
