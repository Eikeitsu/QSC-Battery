/** 更新通道：与 APP UpdateChannel 对齐 */

export const UPDATE_CHANNELS = ["stable", "prerelease", "ci"] as const;
export type UpdateChannel = (typeof UPDATE_CHANNELS)[number];

export const UPDATE_CHANNEL_LABEL: Record<UpdateChannel, string> = {
  stable: "正式",
  prerelease: "预发布",
  ci: "CI",
};

export const UPDATE_CHANNEL_HINT: Record<UpdateChannel, string> = {
  stable: "文档站镜像，与 Magisk 在线更新同源",
  prerelease: "GitHub 预发布资产，不写文档站",
  ci: "ci-dist 滚动构建，可能不稳定",
};

export const UPDATE_URLS = {
  stableModule: "https://eikeitsu.github.io/QSC-Battery/update.json",
  stableApp: "https://eikeitsu.github.io/QSC-Battery/app-update.json",
  ciModule: "https://raw.githubusercontent.com/Eikeitsu/QSC-Battery/ci-dist/update.json",
  ciApp: "https://raw.githubusercontent.com/Eikeitsu/QSC-Battery/ci-dist/app-update.json",
  githubReleases: "https://api.github.com/repos/Eikeitsu/QSC-Battery/releases",
} as const;

export interface RemoteUpdateInfo {
  version: string;
  versionCode: number;
  zipUrl?: string;
  apkUrl?: string;
  changelog?: string;
}

export interface ChannelCheckResult {
  channel: UpdateChannel;
  module: RemoteUpdateInfo | null;
  app: RemoteUpdateInfo | null;
  stableModuleNewer: RemoteUpdateInfo | null;
  stableAppNewer: RemoteUpdateInfo | null;
  error: string | null;
}

export function parseUpdateChannel(raw: string | null | undefined): UpdateChannel {
  if (raw === "prerelease" || raw === "ci") return raw;
  return "stable";
}

function parseJsonUpdate(text: string): RemoteUpdateInfo {
  const obj = JSON.parse(text) as Record<string, unknown>;
  return {
    version: String(obj.version ?? ""),
    versionCode: Number(obj.versionCode ?? 0),
    zipUrl: obj.zipUrl ? String(obj.zipUrl) : undefined,
    apkUrl: obj.apkUrl ? String(obj.apkUrl) : undefined,
    changelog: obj.changelog ? String(obj.changelog) : undefined,
  };
}

async function fetchJsonUpdate(url: string): Promise<RemoteUpdateInfo> {
  const resp = await fetch(url, {
    headers: { "User-Agent": "QSC-Battery-WebUI" },
  });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return parseJsonUpdate(await resp.text());
}

function parseVersionCodeFromBody(body: string): number | null {
  const m =
    /versionCode\s*[=:]\s*(\d+)/.exec(body) ||
    /<!--\s*qsc:versionCode=(\d+)\s*-->/.exec(body);
  return m ? Number(m[1]) : null;
}

async function fetchPrerelease(): Promise<RemoteUpdateInfo> {
  const resp = await fetch(UPDATE_URLS.githubReleases, {
    headers: {
      Accept: "application/vnd.github+json",
      "User-Agent": "QSC-Battery-WebUI",
    },
  });
  if (!resp.ok) throw new Error(`GitHub Releases HTTP ${resp.status}`);
  const arr = (await resp.json()) as Array<Record<string, unknown>>;
  for (const obj of arr) {
    if (obj.draft === true || obj.prerelease !== true) continue;
    const tag = String(obj.tag_name ?? "");
    if (/^ci/i.test(tag) || /ci-latest/i.test(tag)) continue;
    const body = String(obj.body ?? "");
    const code = parseVersionCodeFromBody(body);
    if (code == null) continue;
    const assets = (obj.assets as Array<Record<string, unknown>>) || [];
    let zipUrl: string | undefined;
    let apkUrl: string | undefined;
    let version = tag.replace(/^v/i, "");
    for (const a of assets) {
      const name = String(a.name ?? "");
      const url = a.browser_download_url ? String(a.browser_download_url) : undefined;
      if (name.endsWith("-full.zip")) {
        zipUrl = url;
        const m = /QSC-Battery_v(.+)-full\.zip/.exec(name);
        if (m) version = m[1];
      } else if (name.endsWith(".apk") && name.startsWith("QSC-Battery")) {
        apkUrl = url;
      }
    }
    if (!zipUrl && !apkUrl) continue;
    return {
      version,
      versionCode: code,
      zipUrl,
      apkUrl,
      changelog: obj.html_url ? String(obj.html_url) : undefined,
    };
  }
  throw new Error("暂无可用的预发布");
}

export async function checkUpdateChannel(
  channel: UpdateChannel,
): Promise<ChannelCheckResult> {
  let error: string | null = null;
  let module: RemoteUpdateInfo | null = null;
  let app: RemoteUpdateInfo | null = null;
  try {
    if (channel === "stable") {
      module = await fetchJsonUpdate(UPDATE_URLS.stableModule);
      app = await fetchJsonUpdate(UPDATE_URLS.stableApp).catch(() => null);
    } else if (channel === "ci") {
      module = await fetchJsonUpdate(UPDATE_URLS.ciModule);
      app = await fetchJsonUpdate(UPDATE_URLS.ciApp).catch(() => null);
    } else {
      const pre = await fetchPrerelease();
      module = pre;
      app = pre.apkUrl ? pre : null;
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }

  let stableModuleNewer: RemoteUpdateInfo | null = null;
  let stableAppNewer: RemoteUpdateInfo | null = null;
  if (channel !== "stable") {
    const sm = await fetchJsonUpdate(UPDATE_URLS.stableModule).catch(() => null);
    const sa = await fetchJsonUpdate(UPDATE_URLS.stableApp).catch(() => null);
    if (sm && (!module || sm.versionCode > module.versionCode)) {
      // 旁路：相对「当前通道远端」或至少有正式包时提示；与 APP 一致用「大于本地」更准，
      // WebUI 无本地 module.prop 时改为：正式 code 存在且（无当前远端或正式更新）
      stableModuleNewer = sm;
    }
    if (sa) stableAppNewer = sa;
    // 收紧：仅当正式 versionCode 严格大于当前通道远端时提示，避免误报
    if (sm && module && sm.versionCode <= module.versionCode) {
      stableModuleNewer = null;
    }
    if (sa && app && sa.versionCode <= app.versionCode) {
      stableAppNewer = null;
    }
    if (sa && !app) {
      stableAppNewer = sa;
    }
  }

  return {
    channel,
    module,
    app,
    stableModuleNewer,
    stableAppNewer,
    error,
  };
}
