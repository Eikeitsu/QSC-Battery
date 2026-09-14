/** 更新通道：与 APP UpdateChannel 对齐；元数据统一读 updates 分支 */

export const UPDATE_CHANNELS = ["stable", "prerelease", "ci"] as const;
export type UpdateChannel = (typeof UPDATE_CHANNELS)[number];

export const UPDATE_CHANNEL_LABEL: Record<UpdateChannel, string> = {
  stable: "正式",
  prerelease: "预发布",
  ci: "CI",
};

export const UPDATE_CHANNEL_HINT: Record<UpdateChannel, string> = {
  stable: "updates/stable（包 URL 指向 Pages；Magisk 仍只认 Pages）",
  prerelease: "updates/prerelease → GitHub Release 资产",
  ci: "updates/ci → ci-dist 完整产物",
};

const UPDATES = "https://raw.githubusercontent.com/Eikeitsu/QSC-Battery/updates";

export const UPDATE_URLS = {
  stableModule: `${UPDATES}/stable/update.json`,
  stableApp: `${UPDATES}/stable/app-update.json`,
  stableDaemon: `${UPDATES}/stable/qscd/manifest.json`,
  preModule: `${UPDATES}/prerelease/update.json`,
  preApp: `${UPDATES}/prerelease/app-update.json`,
  preDaemon: `${UPDATES}/prerelease/qscd/manifest.json`,
  ciModule: `${UPDATES}/ci/update.json`,
  ciApp: `${UPDATES}/ci/app-update.json`,
  ciDaemon: `${UPDATES}/ci/qscd/manifest.json`,
} as const;

export interface RemoteUpdateInfo {
  version: string;
  versionCode: number;
  zipUrl?: string;
  apkUrl?: string;
  changelog?: string;
  baseUrl?: string;
  manifestUrl?: string;
}

export interface ChannelCheckResult {
  channel: UpdateChannel;
  module: RemoteUpdateInfo | null;
  app: RemoteUpdateInfo | null;
  daemon: RemoteUpdateInfo | null;
  stableModuleNewer: RemoteUpdateInfo | null;
  stableAppNewer: RemoteUpdateInfo | null;
  stableDaemonNewer: RemoteUpdateInfo | null;
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
    baseUrl: obj.baseUrl ? String(obj.baseUrl) : undefined,
  };
}

async function fetchJsonUpdate(url: string): Promise<RemoteUpdateInfo> {
  const resp = await fetch(url, {
    headers: { "User-Agent": "QSC-Battery-WebUI" },
  });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return parseJsonUpdate(await resp.text());
}

async function fetchDaemon(url: string): Promise<RemoteUpdateInfo> {
  const info = await fetchJsonUpdate(url);
  return { ...info, manifestUrl: url };
}

function urlsFor(channel: UpdateChannel) {
  if (channel === "ci") {
    return {
      module: UPDATE_URLS.ciModule,
      app: UPDATE_URLS.ciApp,
      daemon: UPDATE_URLS.ciDaemon,
    };
  }
  if (channel === "prerelease") {
    return {
      module: UPDATE_URLS.preModule,
      app: UPDATE_URLS.preApp,
      daemon: UPDATE_URLS.preDaemon,
    };
  }
  return {
    module: UPDATE_URLS.stableModule,
    app: UPDATE_URLS.stableApp,
    daemon: UPDATE_URLS.stableDaemon,
  };
}

export async function checkUpdateChannel(
  channel: UpdateChannel,
): Promise<ChannelCheckResult> {
  let error: string | null = null;
  let module: RemoteUpdateInfo | null = null;
  let app: RemoteUpdateInfo | null = null;
  let daemon: RemoteUpdateInfo | null = null;
  const u = urlsFor(channel);
  try {
    module = await fetchJsonUpdate(u.module);
    app = await fetchJsonUpdate(u.app).catch(() => null);
    daemon = await fetchDaemon(u.daemon).catch(() => null);
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }

  let stableModuleNewer: RemoteUpdateInfo | null = null;
  let stableAppNewer: RemoteUpdateInfo | null = null;
  let stableDaemonNewer: RemoteUpdateInfo | null = null;
  if (channel !== "stable") {
    const sm = await fetchJsonUpdate(UPDATE_URLS.stableModule).catch(() => null);
    const sa = await fetchJsonUpdate(UPDATE_URLS.stableApp).catch(() => null);
    const sd = await fetchDaemon(UPDATE_URLS.stableDaemon).catch(() => null);
    if (sm && (!module || sm.versionCode > module.versionCode)) {
      stableModuleNewer = sm;
    }
    if (sa && (!app || sa.versionCode > app.versionCode)) {
      stableAppNewer = sa;
    }
    if (sd && (!daemon || sd.versionCode > daemon.versionCode)) {
      stableDaemonNewer = sd;
    }
    if (sm && module && sm.versionCode <= module.versionCode) {
      stableModuleNewer = null;
    }
    if (sa && app && sa.versionCode <= app.versionCode) {
      stableAppNewer = null;
    }
    if (sd && daemon && sd.versionCode <= daemon.versionCode) {
      stableDaemonNewer = null;
    }
  }

  return {
    channel,
    module,
    app,
    daemon,
    stableModuleNewer,
    stableAppNewer,
    stableDaemonNewer,
    error,
  };
}
