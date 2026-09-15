/**
 * 更新通道资源路由。
 *
 * 检测：一律读 `updates` 分支元数据（stable / prerelease / ci）。
 * 下载（由元数据 URL 决定）：
 * - 正式：Pages（eikeitsu.github.io/…）
 * - 预发布：GitHub Release `…/releases/download/<tag>/…`
 * - CI：`ci-dist`（jsDelivr 或 raw）
 *
 * 「使用 CDN」只影响 updates / ci-dist / raw ↔ jsDelivr；Pages 与 Release 原样保留。
 */
import { STORAGE_KEYS, readStorageFlag, writeStorageFlag } from "@/shared/config/storage";

const OWNER_REPO = "Eikeitsu/QSC-Battery";

type StringLike = string | null | undefined;

/** 默认关：读 updates / ci-dist 走 GitHub raw；开则走 jsDelivr */
export function isPreferCdn(): boolean {
  return readStorageFlag(STORAGE_KEYS.preferCdn, false);
}

export function setPreferCdn(on: boolean): void {
  writeStorageFlag(STORAGE_KEYS.preferCdn, on);
}

function ghRaw(branch: string, path: string): string {
  return `https://raw.githubusercontent.com/${OWNER_REPO}/${branch}/${path.replace(/^\//, "")}`;
}

function ghCdn(branch: string, path: string): string {
  return `https://cdn.jsdelivr.net/gh/${OWNER_REPO}@${branch}/${path.replace(/^\//, "")}`;
}

function host(branch: string, path: string): string {
  return isPreferCdn() ? ghCdn(branch, path) : ghRaw(branch, path);
}

/** updates 分支元数据根 */
export function updatesMetaBase(): string {
  return isPreferCdn()
    ? `https://cdn.jsdelivr.net/gh/${OWNER_REPO}@updates`
    : `https://raw.githubusercontent.com/${OWNER_REPO}/updates`;
}

/**
 * 仅归一 git 托管地址（updates / ci-dist / raw）。
 * GitHub Release、Pages 原样返回——正式/预发布包必须用 Release 公开链接。
 */
export function toChannelAssetUrl(url: StringLike): string {
  const u = String(url || "").trim();
  if (!u) return u;

  // Release / tag 页：不动
  if (/^https:\/\/github\.com\/[^/]+\/[^/]+\/releases\//.test(u)) return u;

  // Pages：不动（Magisk / 策略页 / 旧 tip）；正式通道发版后应写 Release URL
  if (u.includes("eikeitsu.github.io/QSC-Battery")) return u;

  const cdn = /^https:\/\/cdn\.jsdelivr\.net\/gh\/([^/]+)\/([^/]+)@([^/]+)\/(.*)$/.exec(
    u,
  );
  if (cdn) return host(cdn[3]!, cdn[4]!);

  const raw =
    /^https:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([^/]+)\/(.*)$/.exec(u);
  if (raw) return host(raw[3]!, raw[4]!);

  return u;
}

/** @deprecated 名称保留；请用 toChannelAssetUrl */
export function preferGithubCdn(url: StringLike): string {
  return toChannelAssetUrl(url);
}

export function rewriteRawToCdn(url: StringLike): string {
  return toChannelAssetUrl(url);
}

export function rewritePagesToCdn(url: StringLike): string {
  return toChannelAssetUrl(url);
}

/** manifest baseUrl → QSCD_PAGES_BASE（去掉末尾 /qscd） */
export function pagesRootForDaemon(baseOrRoot: StringLike): string {
  const rewritten = toChannelAssetUrl(
    String(baseOrRoot || "")
      .trim()
      .replace(/\/+$/, ""),
  );
  if (!rewritten) return "";
  return rewritten.replace(/\/qscd$/, "") || rewritten;
}

/** 改写清单正文里的 raw↔CDN；不动 Release / Pages */
export function rewriteManifestBody(body: string): string {
  return body
    .replace(/https:\/\/raw\.githubusercontent\.com\/[^"\s]+/g, (u) =>
      toChannelAssetUrl(u),
    )
    .replace(/https:\/\/cdn\.jsdelivr\.net\/gh\/[^"\s]+/g, (u) => toChannelAssetUrl(u));
}
