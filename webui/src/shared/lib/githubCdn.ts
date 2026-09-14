/** Rewrite raw.githubusercontent.com → jsDelivr（设备 curl / 部分网络更稳） */
export function preferGithubCdn(url: StringLike): string {
  const u = String(url || "").trim();
  const m =
    /^https:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([^/]+)\/(.*)$/.exec(u);
  if (!m) return u;
  return `https://cdn.jsdelivr.net/gh/${m[1]}/${m[2]}@${m[3]}/${m[4]}`;
}

/** manifest baseUrl 指向 …/qscd；QSCD_PAGES_BASE 需要站点根（会再拼 /qscd/name） */
export function pagesRootForDaemon(baseOrRoot: StringLike): string {
  const rewritten = preferGithubCdn(
    String(baseOrRoot || "")
      .trim()
      .replace(/\/+$/, ""),
  );
  if (!rewritten) return "";
  return rewritten.replace(/\/qscd$/, "") || rewritten;
}

type StringLike = string | null | undefined;
