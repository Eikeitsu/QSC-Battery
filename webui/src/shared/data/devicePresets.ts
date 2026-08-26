import type { DeviceProfileExport } from "@/shared/api/deviceProfile";
import { exec } from "@/shared/api/ksu";
import { DEVICE_PRESETS_URLS } from "@/shared/config/links";
import { readStorage, writeStorage, STORAGE_KEYS } from "@/shared/config/storage";

export type PresetSource = "builtin" | "repo" | "local";

export interface DevicePreset {
  id: string;
  name: string;
  /**
   * 简单匹配模式：
   * - `*`：任意
   * - `xxx*`：前缀匹配
   * - 其它：包含匹配（忽略大小写）
   */
  matches: string[];
  profile: DeviceProfileExport;
  source: PresetSource;
  note?: string;
}

export interface DevicePresetCatalog {
  version: number;
  updated_at?: string;
  presets: DevicePreset[];
}

/** 模块内兜底：仓库缓存为空 / 拉取失败时仍可用 */
export const DEVICE_PRESETS_BUILTIN: DevicePreset[] = [
  {
    id: "builtin.clear_preferred",
    name: "回退到探测（清空 preferred）",
    matches: ["*"],
    profile: {
      preferred_switch: "",
      preferred_start: "",
      preferred_stop: "",
      reassert: "0",
    },
    source: "builtin",
    note: "模块内兜底；点「从仓库更新」可同步社区列表。",
  },
];

function normalize(s: string): string {
  return String(s || "")
    .trim()
    .toLowerCase();
}

export function matchModel(patterns: string[], model: string): boolean {
  const m = normalize(model);
  if (!m) return false;
  const ps = (patterns || []).map((p) => normalize(p)).filter(Boolean);
  if (!ps.length) return false;
  return ps.some((p) => {
    if (p === "*") return true;
    if (p.endsWith("*")) return m.startsWith(p.slice(0, -1));
    return m.includes(p);
  });
}

export function filterPresetsByModel(
  presets: DevicePreset[],
  model: string,
): DevicePreset[] {
  return presets.filter((p) => matchModel(p.matches, model));
}

function coercePreset(raw: unknown, source: PresetSource): DevicePreset | null {
  if (!raw || typeof raw !== "object") return null;
  const x = raw as Record<string, unknown>;
  if (typeof x.id !== "string" || !x.id.trim()) return null;
  if (typeof x.name !== "string" || !x.name.trim()) return null;
  if (!Array.isArray(x.matches)) return null;
  if (!x.profile || typeof x.profile !== "object") return null;
  return {
    id: x.id.trim(),
    name: x.name.trim(),
    matches: x.matches.map((v) => String(v)),
    profile: x.profile as DeviceProfileExport,
    source,
    note: typeof x.note === "string" ? x.note : undefined,
  };
}

export function parseDevicePresetCatalog(
  text: string,
  source: PresetSource,
): DevicePresetCatalog {
  const parsed = JSON.parse(String(text || "")) as Record<string, unknown>;
  const list = Array.isArray(parsed.presets)
    ? parsed.presets
    : Array.isArray(parsed)
      ? parsed
      : [];
  const presets = list
    .map((item) => coercePreset(item, source))
    .filter(Boolean) as DevicePreset[];
  return {
    version: typeof parsed.version === "number" ? parsed.version : 1,
    updated_at: typeof parsed.updated_at === "string" ? parsed.updated_at : undefined,
    presets,
  };
}

const USER_KEY = STORAGE_KEYS.devicePresetsUser;
const REPO_KEY = STORAGE_KEYS.devicePresetsRepo;
const REPO_META_KEY = STORAGE_KEYS.devicePresetsRepoMeta;

export function loadLocalDevicePresets(): DevicePreset[] {
  const raw = readStorage(USER_KEY);
  if (!raw) return [];
  try {
    const catalog = parseDevicePresetCatalog(raw, "local");
    // 兼容旧版：直接存数组
    if (!catalog.presets.length && raw.trim().startsWith("[")) {
      const arr = JSON.parse(raw) as unknown[];
      return arr
        .map((item) => coercePreset(item, "local"))
        .filter(Boolean) as DevicePreset[];
    }
    return catalog.presets.map((p) => ({ ...p, source: "local" as const }));
  } catch {
    try {
      const arr = JSON.parse(raw) as unknown[];
      if (!Array.isArray(arr)) return [];
      return arr
        .map((item) => coercePreset(item, "local"))
        .filter(Boolean) as DevicePreset[];
    } catch {
      return [];
    }
  }
}

/** @deprecated 使用 loadLocalDevicePresets */
export const loadUserDevicePresets = loadLocalDevicePresets;

export function saveLocalDevicePresets(list: DevicePreset[]): void {
  const payload: DevicePresetCatalog = {
    version: 1,
    updated_at: new Date().toISOString().slice(0, 10),
    presets: list.map((p) => ({
      ...p,
      source: "local",
    })),
  };
  writeStorage(USER_KEY, JSON.stringify(payload));
}

/** @deprecated 使用 saveLocalDevicePresets */
export const saveUserDevicePresets = saveLocalDevicePresets;

export interface RepoPresetCacheMeta {
  updated_at?: string;
  fetched_at?: string;
  count?: number;
  url?: string;
}

export function loadRepoPresetCache(): {
  presets: DevicePreset[];
  meta: RepoPresetCacheMeta;
} {
  const metaRaw = readStorage(REPO_META_KEY);
  let meta: RepoPresetCacheMeta = {};
  if (metaRaw) {
    try {
      meta = JSON.parse(metaRaw) as RepoPresetCacheMeta;
    } catch {
      meta = {};
    }
  }
  const raw = readStorage(REPO_KEY);
  if (!raw) {
    return { presets: [], meta };
  }
  try {
    const catalog = parseDevicePresetCatalog(raw, "repo");
    return {
      presets: catalog.presets.map((p) => ({ ...p, source: "repo" as const })),
      meta: {
        ...meta,
        updated_at: catalog.updated_at || meta.updated_at,
        count: catalog.presets.length,
      },
    };
  } catch {
    return { presets: [], meta };
  }
}

export function saveRepoPresetCache(catalog: DevicePresetCatalog, url: string): void {
  const body: DevicePresetCatalog = {
    version: catalog.version || 1,
    updated_at: catalog.updated_at,
    presets: catalog.presets.map(({ id, name, matches, profile, note }) => ({
      id,
      name,
      matches,
      profile,
      note,
      source: "repo",
    })),
  };
  writeStorage(REPO_KEY, JSON.stringify(body));
  const meta: RepoPresetCacheMeta = {
    updated_at: catalog.updated_at,
    fetched_at: new Date().toISOString(),
    count: body.presets.length,
    url,
  };
  writeStorage(REPO_META_KEY, JSON.stringify(meta));
}

/** 仓库列表展示用：有缓存用缓存，否则用模块内兜底 */
export function resolveRepoPresetsForDisplay(cached: DevicePreset[]): DevicePreset[] {
  return cached.length ? cached : DEVICE_PRESETS_BUILTIN;
}

async function fetchTextViaHttp(url: string): Promise<string | null> {
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 12_000);
    const res = await fetch(url, {
      method: "GET",
      cache: "no-store",
      signal: ctrl.signal,
    });
    clearTimeout(timer);
    if (!res.ok) return null;
    return await res.text();
  } catch {
    return null;
  }
}

async function fetchTextViaShell(url: string): Promise<string | null> {
  const safe = String(url || "").replace(/'/g, "");
  const result = await exec(
    `(curl -fsSL '${safe}' 2>/dev/null || wget -qO- '${safe}' 2>/dev/null)`,
    20_000,
  );
  const text = (result.stdout || "").trim();
  if (result.errno !== 0 || !text) return null;
  return text;
}

export async function fetchRepoDevicePresets(
  urls: string[] = [...DEVICE_PRESETS_URLS],
): Promise<{ catalog: DevicePresetCatalog; url: string }> {
  let lastError = "无法拉取仓库预制档";
  for (const url of urls) {
    let text = await fetchTextViaHttp(url);
    if (!text) text = await fetchTextViaShell(url);
    if (!text) {
      lastError = `拉取失败：${url}`;
      continue;
    }
    try {
      const catalog = parseDevicePresetCatalog(text, "repo");
      if (!catalog.presets.length) {
        lastError = `仓库列表为空：${url}`;
        continue;
      }
      return { catalog, url };
    } catch (e) {
      lastError = `解析失败：${String((e as Error)?.message || e)}`;
    }
  }
  throw new Error(lastError);
}

export async function updateRepoPresetsFromRemote(): Promise<{
  count: number;
  updated_at?: string;
  url: string;
}> {
  const { catalog, url } = await fetchRepoDevicePresets();
  saveRepoPresetCache(catalog, url);
  return {
    count: catalog.presets.length,
    updated_at: catalog.updated_at,
    url,
  };
}
