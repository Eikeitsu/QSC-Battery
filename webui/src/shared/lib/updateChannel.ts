/** 更新通道：WebUI 只检模块 + 守护（不检伴侣 APP） */

import { readLocalModule } from "@/shared/api/moduleUpdate";

export const UPDATE_CHANNELS = ["stable", "prerelease", "ci"] as const;
export type UpdateChannel = (typeof UPDATE_CHANNELS)[number];

export const UPDATE_CHANNEL_LABEL: Record<UpdateChannel, string> = {
  stable: "正式",
  prerelease: "预发布",
  ci: "CI",
};

export const UPDATE_CHANNEL_HINT: Record<UpdateChannel, string> = {
  stable: "推荐大多数用户",
  prerelease: "尝鲜功能，可能不稳定",
  ci: "开发构建，风险较高",
};

export const UPDATE_CHANNEL_TECH: Record<UpdateChannel, string> = {
  stable: "正式：updates/stable；包地址通常指向 Pages。Magisk 仍只认 Pages update.json。",
  prerelease: "预发布：updates/prerelease → GitHub Release 资产",
  ci: "CI：updates/ci → ci-dist 完整产物",
};

const UPDATES = "https://raw.githubusercontent.com/Eikeitsu/QSC-Battery/updates";

export const UPDATE_URLS = {
  stableModule: `${UPDATES}/stable/update.json`,
  stableDaemon: `${UPDATES}/stable/qscd/manifest.json`,
  preModule: `${UPDATES}/prerelease/update.json`,
  preDaemon: `${UPDATES}/prerelease/qscd/manifest.json`,
  ciModule: `${UPDATES}/ci/update.json`,
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
  moduleLocalVersion: string;
  moduleLocalCode: number;
  module: RemoteUpdateInfo | null;
  moduleHasUpdate: boolean;
  daemonLocalVersion: string;
  daemonLocalCode: number;
  daemon: RemoteUpdateInfo | null;
  daemonHasUpdate: boolean;
  stableModuleNewer: RemoteUpdateInfo | null;
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
    return { module: UPDATE_URLS.ciModule, daemon: UPDATE_URLS.ciDaemon };
  }
  if (channel === "prerelease") {
    return { module: UPDATE_URLS.preModule, daemon: UPDATE_URLS.preDaemon };
  }
  return { module: UPDATE_URLS.stableModule, daemon: UPDATE_URLS.stableDaemon };
}

async function readDaemonLocal(): Promise<{ version: string; code: number }> {
  const { exec } = await import("@/shared/api/ksu");
  const { PATHS } = await import("@/shared/config/paths");
  const r = await exec(
    `cat '${PATHS.DATADIR}/native_version' 2>/dev/null; echo ---; cat '${PATHS.DATADIR}/native_version_code' 2>/dev/null`,
    5_000,
  );
  const parts = (r.stdout || "").split("---");
  const version = (parts[0] || "").trim();
  const code = Number((parts[1] || "").trim()) || 0;
  return { version, code };
}

export async function checkUpdateChannel(
  channel: UpdateChannel,
): Promise<ChannelCheckResult> {
  let error: string | null = null;
  let module: RemoteUpdateInfo | null = null;
  let daemon: RemoteUpdateInfo | null = null;
  const u = urlsFor(channel);
  try {
    module = await fetchJsonUpdate(u.module);
    daemon = await fetchDaemon(u.daemon).catch(() => null);
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }

  const localMod = await readLocalModule().catch(() => null);
  const localDaemon = await readDaemonLocal().catch(() => ({ version: "", code: 0 }));
  const moduleLocalCode = localMod?.versionCode ?? 0;
  const moduleHasUpdate = !!(
    module &&
    module.versionCode > 0 &&
    module.versionCode > moduleLocalCode
  );
  const daemonHasUpdate = !!(
    daemon &&
    daemon.versionCode > 0 &&
    daemon.versionCode > localDaemon.code
  );

  let stableModuleNewer: RemoteUpdateInfo | null = null;
  let stableDaemonNewer: RemoteUpdateInfo | null = null;
  if (channel !== "stable") {
    const sm = await fetchJsonUpdate(UPDATE_URLS.stableModule).catch(() => null);
    const sd = await fetchDaemon(UPDATE_URLS.stableDaemon).catch(() => null);
    if (sm && sm.versionCode > moduleLocalCode) stableModuleNewer = sm;
    if (sd && sd.versionCode > localDaemon.code) stableDaemonNewer = sd;
  }

  return {
    channel,
    moduleLocalVersion: localMod?.version || "",
    moduleLocalCode,
    module,
    moduleHasUpdate,
    daemonLocalVersion: localDaemon.version,
    daemonLocalCode: localDaemon.code,
    daemon,
    daemonHasUpdate,
    stableModuleNewer,
    stableDaemonNewer,
    error,
  };
}
