/** 更新通道：WebUI 只检模块 + 守护（不检伴侣 APP）；资产走 updates/ci-dist，不走 Pages 站点 */

import { readLocalModule } from "@/shared/api/moduleUpdate";
import { updatesMetaBase, toChannelAssetUrl } from "@/shared/lib/githubCdn";

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
  stable: "正式：updates/stable 检测；模块/APP/守护下载 Pages",
  prerelease: "预发布：updates/prerelease 检测；下载对应预发布 Release 资产",
  ci: "CI：updates/ci 检测；下载 ci-dist 产物",
};

export function channelUpdateUrls(channel: UpdateChannel = "stable") {
  const base = updatesMetaBase();
  const seg =
    channel === "ci" ? "ci" : channel === "prerelease" ? "prerelease" : "stable";
  return {
    module: `${base}/${seg}/update.json`,
    daemon: `${base}/${seg}/qscd/manifest.json`,
  };
}

/** @deprecated 动态 URL 请用 channelUpdateUrls()；保留静态字段避免旧引用炸掉 */
export const UPDATE_URLS = {
  get stableModule() {
    return channelUpdateUrls("stable").module;
  },
  get stableDaemon() {
    return channelUpdateUrls("stable").daemon;
  },
  get preModule() {
    return channelUpdateUrls("prerelease").module;
  },
  get preDaemon() {
    return channelUpdateUrls("prerelease").daemon;
  },
  get ciModule() {
    return channelUpdateUrls("ci").module;
  },
  get ciDaemon() {
    return channelUpdateUrls("ci").daemon;
  },
} as const;

export interface RemoteUpdateInfo {
  version: string;
  versionCode: number;
  zipUrl?: string;
  apkUrl?: string;
  changelog?: string;
  baseUrl?: string;
  manifestUrl?: string;
  rustVersion?: string;
  rustVersionCode?: number;
  cVersion?: string;
  cVersionCode?: number;
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
  daemonImpl: "rust" | "c";
  /** 本地未安装守护时为 true */
  daemonMissing: boolean;
  stableModuleNewer: RemoteUpdateInfo | null;
  stableDaemonNewer: RemoteUpdateInfo | null;
  error: string | null;
}

export function parseUpdateChannel(raw: string | null | undefined): UpdateChannel {
  if (raw === "prerelease" || raw === "ci") return raw;
  return "stable";
}

/** 展示用：空本地显示「未知」 */
export function versionLine(local?: string | null, remote?: string | null): string {
  const l = (local || "").trim() || "未知";
  const r = (remote || "").trim() || "--";
  return l === r ? l : `${l} → ${r}`;
}

function parseJsonUpdate(text: string): RemoteUpdateInfo {
  const obj = JSON.parse(text) as Record<string, unknown>;
  return {
    version: String(obj.version ?? ""),
    versionCode: Number(obj.versionCode ?? 0),
    zipUrl: obj.zipUrl ? toChannelAssetUrl(String(obj.zipUrl)) : undefined,
    apkUrl: obj.apkUrl ? toChannelAssetUrl(String(obj.apkUrl)) : undefined,
    changelog: obj.changelog ? String(obj.changelog) : undefined,
    baseUrl: obj.baseUrl ? toChannelAssetUrl(String(obj.baseUrl)) : undefined,
    rustVersion: obj.rustVersion ? String(obj.rustVersion) : undefined,
    rustVersionCode:
      obj.rustVersionCode != null ? Number(obj.rustVersionCode) : undefined,
    cVersion: obj.cVersion ? String(obj.cVersion) : undefined,
    cVersionCode: obj.cVersionCode != null ? Number(obj.cVersionCode) : undefined,
  };
}

function versionForImpl(info: RemoteUpdateInfo, impl: "rust" | "c"): string {
  if (impl === "c") return info.cVersion || info.version;
  return info.rustVersion || info.version;
}

function versionCodeForImpl(info: RemoteUpdateInfo, impl: "rust" | "c"): number {
  if (impl === "c") {
    return info.cVersionCode && info.cVersionCode > 0
      ? info.cVersionCode
      : info.versionCode;
  }
  return info.rustVersionCode && info.rustVersionCode > 0
    ? info.rustVersionCode
    : info.versionCode;
}

function forImpl(info: RemoteUpdateInfo, impl: "rust" | "c"): RemoteUpdateInfo {
  return {
    ...info,
    version: versionForImpl(info, impl),
    versionCode: versionCodeForImpl(info, impl),
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

async function readDaemonLocal(
  impl: "rust" | "c",
): Promise<{ version: string; code: number }> {
  const { exec } = await import("@/shared/api/ksu");
  const { PATHS } = await import("@/shared/config/paths");
  const side = impl === "c" ? "c" : "rust";
  const r = await exec(
    `cat '${PATHS.DATADIR}/native_version_${side}' 2>/dev/null; echo ---; ` +
      `cat '${PATHS.DATADIR}/native_version_code_${side}' 2>/dev/null; echo ---; ` +
      `cat '${PATHS.DATADIR}/native_version' 2>/dev/null; echo ---; ` +
      `cat '${PATHS.DATADIR}/native_version_code' 2>/dev/null; echo ---; ` +
      `cat '${PATHS.DATADIR}/native_impl_used' 2>/dev/null`,
    5_000,
  );
  const parts = (r.stdout || "").split("---").map((s) => s.trim());
  const sideVer = parts[0] || "";
  const sideCode = Number(parts[1] || "") || 0;
  const tipVer = parts[2] || "";
  const tipCode = Number(parts[3] || "") || 0;
  const used = (parts[4] || "").toLowerCase();
  if (sideVer || sideCode) {
    return { version: sideVer, code: sideCode };
  }
  if (used === impl || !used) {
    return { version: tipVer, code: tipCode };
  }
  return { version: "", code: 0 };
}

async function preferredDaemonImpl(): Promise<"rust" | "c"> {
  const { exec } = await import("@/shared/api/ksu");
  const { PATHS } = await import("@/shared/config/paths");
  const r = await exec(
    `cat '${PATHS.DATADIR}/native_impl_used' 2>/dev/null; echo ---; ` +
      `sed -n 's/^native_impl=//p' '${PATHS.CONF}' 2>/dev/null | head -1`,
    5_000,
  );
  const parts = (r.stdout || "").split("---").map((s) => s.trim().toLowerCase());
  if (parts[0] === "c" || parts[0] === "rust") return parts[0];
  if (parts[1] === "c") return "c";
  return "rust";
}

export async function checkUpdateChannel(
  channel: UpdateChannel,
): Promise<ChannelCheckResult> {
  let error: string | null = null;
  let module: RemoteUpdateInfo | null = null;
  let daemonRaw: RemoteUpdateInfo | null = null;
  const u = channelUpdateUrls(channel);
  try {
    module = await fetchJsonUpdate(u.module);
    daemonRaw = await fetchDaemon(u.daemon).catch(() => null);
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }

  const daemonImpl = await preferredDaemonImpl().catch(() => "rust" as const);
  const localMod = await readLocalModule().catch(() => null);
  const localDaemon = await readDaemonLocal(daemonImpl).catch(() => ({
    version: "",
    code: 0,
  }));
  const moduleLocalCode = localMod?.versionCode ?? 0;
  const moduleHasUpdate = !!(
    module &&
    module.versionCode > 0 &&
    module.versionCode > moduleLocalCode
  );
  const daemon = daemonRaw ? forImpl(daemonRaw, daemonImpl) : null;
  const daemonMissing = !localDaemon.version && !localDaemon.code;
  const daemonHasUpdate = !!(
    daemon &&
    daemon.versionCode > 0 &&
    (daemonMissing || daemon.versionCode > localDaemon.code)
  );

  let stableModuleNewer: RemoteUpdateInfo | null = null;
  let stableDaemonNewer: RemoteUpdateInfo | null = null;
  if (channel !== "stable") {
    const stableUrls = channelUpdateUrls("stable");
    const sm = await fetchJsonUpdate(stableUrls.module).catch(() => null);
    const sd = await fetchDaemon(stableUrls.daemon).catch(() => null);
    if (sm && sm.versionCode > moduleLocalCode) stableModuleNewer = sm;
    if (sd) {
      const sdi = forImpl(sd, daemonImpl);
      if (daemonMissing || sdi.versionCode > localDaemon.code) {
        stableDaemonNewer = sdi;
      }
    }
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
    daemonImpl,
    daemonMissing,
    stableModuleNewer,
    stableDaemonNewer,
    error,
  };
}
