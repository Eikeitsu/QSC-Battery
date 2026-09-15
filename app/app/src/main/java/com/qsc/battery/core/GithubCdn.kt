package com.qsc.battery.core

/**
 * 更新通道：
 * - 元数据：updates 分支（可走 jsDelivr）
 * - 正式：Pages；预发布：GitHub Release；CI：ci-dist
 *
 * 「使用 CDN」只影响 updates / ci-dist / raw ↔ jsDelivr；Pages 与 Release 原样保留。
 */
object GithubCdn {
    private val RAW = Regex(
        """^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.*)$""",
    )
    private val CDN = Regex(
        """^https://cdn\.jsdelivr\.net\/gh\/([^/]+)\/([^/]+)@([^/]+)\/(.*)$""",
    )

    /** raw ↔ jsDelivr；Release / Pages 原样返回 */
    fun toChannelAssetUrl(url: String, preferCdn: Boolean): String {
        val u = url.trim()
        if (u.isEmpty()) return u
        if (u.contains("github.com/") && u.contains("/releases/")) return u
        if (u.contains("eikeitsu.github.io/QSC-Battery")) return u
        CDN.matchEntire(u)?.let { m ->
            val (owner, repo, branch, path) = m.destructured
            return if (preferCdn) {
                u
            } else {
                "https://raw.githubusercontent.com/$owner/$repo/$branch/$path"
            }
        }
        RAW.matchEntire(u)?.let { m ->
            val (owner, repo, branch, path) = m.destructured
            return if (preferCdn) {
                "https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$path"
            } else {
                "https://raw.githubusercontent.com/$owner/$repo/$branch/$path"
            }
        }
        return u
    }

    /** @deprecated 语义同 [toChannelAssetUrl] preferCdn=true */
    fun preferReachable(url: String): String = toChannelAssetUrl(url, true)

    fun forCiMeta(url: String, preferCdn: Boolean): String = toChannelAssetUrl(url, preferCdn)

    fun pagesRootForDaemon(baseOrRoot: String?, preferCdn: Boolean = false): String? {
        if (baseOrRoot.isNullOrBlank()) return null
        val rewritten = toChannelAssetUrl(baseOrRoot.trim().trimEnd('/'), preferCdn)
        return rewritten.removeSuffix("/qscd").ifBlank { rewritten }
    }

    fun rewriteManifestBody(body: String, preferCdn: Boolean = false): String {
        fun map(u: String) = toChannelAssetUrl(u, preferCdn)
        return body
            .replace(Regex("""https://raw\.githubusercontent\.com/[^"\s]+""")) { map(it.value) }
            .replace(Regex("""https://cdn\.jsdelivr\.net/gh/[^"\s]+""")) { map(it.value) }
    }
}
