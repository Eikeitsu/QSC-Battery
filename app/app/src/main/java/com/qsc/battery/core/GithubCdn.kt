/**
 * 更新通道：
 * - 元数据：updates 分支（可走 jsDelivr）
 * - 正式：Pages；预发布：GitHub Release；CI：ci-dist
 */
object GithubCdn {
    private val RAW = Regex(
        """^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.*)$""",
    )
    private val CDN = Regex(
        """^https://cdn\.jsdelivr\.net\/gh\/([^/]+)\/([^/]+)@([^/]+)\/(.*)$""",
    )

    /** raw → jsDelivr；Release / Pages 原样返回 */
    fun preferReachable(url: String): String {
        val u = url.trim()
        if (u.isEmpty()) return u
        if (u.contains("github.com/") && u.contains("/releases/")) return u
        if (u.contains("eikeitsu.github.io/QSC-Battery")) return u
        CDN.matchEntire(u)?.let { return u }
        RAW.matchEntire(u)?.let { m ->
            val (owner, repo, branch, path) = m.destructured
            return "https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$path"
        }
        return u
    }

    /** CI 通道：关 CDN 时把 jsDelivr updates/ci-dist 改回 raw */
    fun forCiMeta(url: String, preferCdn: Boolean): String {
        val u = url.trim()
        if (preferCdn) return preferReachable(u)
        CDN.matchEntire(u)?.let { m ->
            val (owner, repo, branch, path) = m.destructured
            if (branch == "updates" || branch == "ci-dist") {
                return "https://raw.githubusercontent.com/$owner/$repo/$branch/$path"
            }
        }
        return u
    }

    fun pagesRootForDaemon(baseOrRoot: String?): String? {
        if (baseOrRoot.isNullOrBlank()) return null
        val rewritten = preferReachable(baseOrRoot.trim().trimEnd('/'))
        return rewritten.removeSuffix("/qscd").ifBlank { rewritten }
    }

    fun rewriteManifestBody(body: String, preferCdn: Boolean = true): String {
        fun map(u: String) = forCiMeta(preferReachable(u), preferCdn)
        return body
            .replace(Regex("""https://raw\.githubusercontent\.com/[^"\s]+""")) { map(it.value) }
            .replace(Regex("""https://cdn\.jsdelivr\.net/gh/[^"\s]+""")) { map(it.value) }
    }
}
