import { CURRENT_DEFAULTS } from "@/shared/config/defaults";
import { BinaryFlag } from "@/shared/config/enums";
import { confFileForKey } from "@/shared/config/confFiles";
import { PATHS } from "@/shared/config/paths";
import { sanitizeCurrentConfig, sanitizePowerStopSchedule } from "@/shared/config/limits";
import type { CurrentConfig, Settings } from "@/shared/types";
import { exec } from "./ksu";
import type { DeviceProfileExport } from "./deviceProfile";

function confPathForKey(key: string): string {
  const kind = confFileForKey(key);
  if (kind === "power") return PATHS.POWER_CONF;
  if (kind === "notify") return PATHS.NOTIFY_CONF;
  return PATHS.CONF;
}

export async function getConf(key: string): Promise<string> {
  const path = confPathForKey(key);
  const result = await exec(
    `grep '^${key}=' '${path}' 2>/dev/null | tail -1 | cut -d= -f2-`,
  );
  return result.stdout.trim();
}

/** 一次 shell 读三个 conf，合并键（后读的同名键覆盖——通常不会重叠） */
export async function loadConfigValues(
  keys: readonly string[],
): Promise<Record<string, string>> {
  const wanted = new Set(keys);
  const values: Record<string, string> = {};
  const result = await exec(
    `printf '%s\\n' "---" ; cat '${PATHS.CONF}' 2>/dev/null; ` +
      `printf '%s\\n' "---" ; cat '${PATHS.POWER_CONF}' 2>/dev/null; ` +
      `printf '%s\\n' "---" ; cat '${PATHS.NOTIFY_CONF}' 2>/dev/null`,
  );
  for (const line of result.stdout.split(/\r?\n/)) {
    if (line === "---") continue;
    const index = line.indexOf("=");
    if (index <= 0) continue;
    const key = line.slice(0, index);
    if (wanted.has(key)) values[key] = line.slice(index + 1).trim();
  }
  return values;
}

export async function notifyConfReload(): Promise<void> {
  await exec(
    `mkdir -p '${PATHS.DATADIR}' 2>/dev/null; : >'${PATHS.CONF_RELOAD_REQ}' 2>/dev/null`,
  );
}

/** 原子删除 key= 行后追加新行（避免 Magisk 目录 sed -i 写 NUL） */
async function replaceMultilineKey(
  path: string,
  key: string,
  lines: string[],
): Promise<boolean> {
  const safeKey = String(key).replace(/[^a-zA-Z0-9_]/g, "");
  if (!safeKey) return false;
  const del = await exec(
    `mkdir -p '${PATHS.MODDIR}/config' 2>/dev/null; ` +
      `f='${path}'; [ -f "$f" ] || printf '# QSC conf\\n' > "$f"; ` +
      `tmp="$f.rm.$$"; ` +
      `awk -v k='${safeKey}' 'index($0,k"=")!=1{print}' "$f" > "$tmp" && ` +
      `mv -f "$tmp" "$f"`,
  );
  if (del.errno !== 0) return false;
  for (const line of lines) {
    const b64 = btoa(unescape(encodeURIComponent(line)));
    const r = await exec(
      `echo '${b64}' | base64 -d >> '${path}' 2>/dev/null || echo '${b64}' | base64 --decode >> '${path}'`,
    );
    if (r.errno !== 0) return false;
  }
  return true;
}

export async function setConf(key: string, value: string | number): Promise<void> {
  const safeKey = String(key).replace(/[^a-zA-Z0-9_]/g, "");
  const safeVal = String(value).replace(/[^0-9A-Za-z._:,-]/g, "");
  const path = confPathForKey(safeKey);
  // 原子改写：Magisk 模块目录上 sed -i 偶发写出 NUL/稀疏文件
  await exec(
    `mkdir -p '${PATHS.MODDIR}/config' 2>/dev/null; ` +
      `f='${path}'; [ -f "$f" ] || printf '# QSC conf\\n' > "$f"; ` +
      `tmp="$f.set.$$"; ` +
      `awk -v k='${safeKey}' -v v='${safeVal}' '` +
      `BEGIN{done=0} { if(!done && index($0,k"=")==1){ print k"="v; done=1 } else print } ` +
      `END{ if(!done) print k"="v }' "$f" > "$tmp" && mv -f "$tmp" "$f"`,
  );
  await notifyConfReload();
}

/** 解析 config.conf 中的 power_switch 行为「路径 start=X stop=Y」列表 */
export async function loadPowerSwitches(): Promise<string[]> {
  const result = await exec(`grep '^power_switch=' '${PATHS.CONF}' 2>/dev/null`);
  const lines = result.stdout
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  const out: string[] = [];
  for (const line of lines) {
    let body = line.replace(/^power_switch=/, "");
    if (body.startsWith("[") && body.endsWith("]")) body = body.slice(1, -1);
    body = body.replace(/::/g, " ").trim();
    if (!body) continue;
    const m = body.match(/^(.+),start=([^,]+),stop=(.+)$/);
    if (m) {
      out.push(`${m[1]} start=${m[2]} stop=${m[3]}`);
      continue;
    }
    out.push(body);
  }
  return out;
}

/**
 * 覆写 power_switch 行。每行可为：
 * - `/path start=1 stop=0`
 * - `power_switch=[/path start=1 stop=0]`
 */
export async function savePowerSwitches(entries: string[]): Promise<boolean> {
  const normalized: string[] = [];
  for (const raw of entries) {
    let s = String(raw || "").trim();
    if (!s || s.startsWith("#")) continue;
    s = s
      .replace(/^power_switch=/, "")
      .replace(/^\[/, "")
      .replace(/\]$/, "")
      .trim();
    s = s.replace(/::/g, " ");
    const mComma = s.match(/^(.+),start=([^,]+),stop=(.+)$/);
    let path: string;
    let start: string;
    let stop: string;
    if (mComma) {
      path = mComma[1].trim();
      start = mComma[2].trim();
      stop = mComma[3].trim();
    } else {
      const m = s.match(/^(\S+)\s+start=(\S+)\s+stop=(\S+)\s*$/);
      if (!m) continue;
      path = m[1];
      start = m[2];
      stop = m[3];
    }
    if (!path.startsWith("/") || !start || !stop) continue;
    const startOut = start.includes(" ") ? start.replace(/ /g, "::") : start;
    const stopOut = stop.includes(" ") ? stop.replace(/ /g, "::") : stop;
    normalized.push(`power_switch=[${path} start=${startOut} stop=${stopOut}]`);
  }
  const ok = await replaceMultilineKey(PATHS.CONF, "power_switch", normalized);
  if (ok) await notifyConfReload();
  return ok;
}

export async function loadPowerStopSchedule(): Promise<string[]> {
  const result = await exec(`grep '^power_stop_schedule=' '${PATHS.CONF}' 2>/dev/null`);
  const raw = result.stdout
    .split(/\r?\n/)
    .map((l) =>
      l
        .replace(/^power_stop_schedule=/, "")
        .replace(/^\[/, "")
        .replace(/\]$/, "")
        .trim(),
    )
    .filter(Boolean);
  return sanitizePowerStopSchedule(raw);
}

export async function savePowerStopSchedule(ranges: string[]): Promise<boolean> {
  const list = sanitizePowerStopSchedule(ranges);
  const lines = list.map((r) => `power_stop_schedule=${r}`);
  const ok = await replaceMultilineKey(PATHS.CONF, "power_stop_schedule", lines);
  if (ok) await notifyConfReload();
  return ok;
}

export async function loadNotifyQuietSchedule(): Promise<string[]> {
  const result = await exec(
    `grep '^notify_quiet_schedule=' '${PATHS.NOTIFY_CONF}' 2>/dev/null`,
  );
  const raw = result.stdout
    .split(/\r?\n/)
    .map((l) =>
      l
        .replace(/^notify_quiet_schedule=/, "")
        .replace(/^\[/, "")
        .replace(/\]$/, "")
        .trim(),
    )
    .filter(Boolean);
  return sanitizePowerStopSchedule(raw);
}

export async function saveNotifyQuietSchedule(ranges: string[]): Promise<boolean> {
  const list = sanitizePowerStopSchedule(ranges);
  const lines = list.map((r) => `notify_quiet_schedule=${r}`);
  const ok = await replaceMultilineKey(PATHS.NOTIFY_CONF, "notify_quiet_schedule", lines);
  if (ok) await notifyConfReload();
  return ok;
}

export async function loadNightSchedule(): Promise<string[]> {
  const result = await exec(`grep '^night_schedule=' '${PATHS.POWER_CONF}' 2>/dev/null`);
  const raw = result.stdout
    .split(/\r?\n/)
    .map((l) =>
      l
        .replace(/^night_schedule=/, "")
        .replace(/^\[/, "")
        .replace(/\]$/, "")
        .trim(),
    )
    .filter(Boolean);
  return sanitizePowerStopSchedule(raw);
}

export async function saveNightSchedule(ranges: string[]): Promise<boolean> {
  const list = sanitizePowerStopSchedule(ranges);
  const lines = list.map((r) => `night_schedule=${r}`);
  const ok = await replaceMultilineKey(PATHS.POWER_CONF, "night_schedule", lines);
  if (ok) await notifyConfReload();
  return ok;
}

export function parseJsonc(text: string): Record<string, unknown> {
  const cleaned = String(text || "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/,\s*([\]}])/g, "$1");
  return JSON.parse(cleaned) as Record<string, unknown>;
}

export async function hasCurrentFeature(): Promise<boolean> {
  const result = await exec(
    `[ -f '${PATHS.CURRENT_CONF}' ] && [ -f '${PATHS.CURRENT_LIB}' ] && echo 1 || echo 0`,
  );
  return result.stdout.trim() === BinaryFlag.On;
}

export function normalizeAppList(value: unknown): string[] {
  return sanitizeCurrentConfig({
    ...CURRENT_DEFAULTS,
    app_list: Array.isArray(value) ? value : String(value || "").split(/\n+/),
  }).value.app_list;
}

export function normalizeScheduleList(value: unknown): string[] {
  return sanitizeCurrentConfig({
    ...CURRENT_DEFAULTS,
    bypass_schedule: Array.isArray(value) ? value : String(value || "").split(/\n+/),
  }).value.bypass_schedule;
}

export async function loadCurrentJsonc(): Promise<CurrentConfig> {
  const result = await exec(`cat '${PATHS.CURRENT_CONF}' 2>/dev/null`);
  if (!result.stdout.trim()) return { ...CURRENT_DEFAULTS };
  try {
    const parsed = parseJsonc(result.stdout) as Partial<CurrentConfig>;
    if (!Object.prototype.hasOwnProperty.call(parsed, "bypass_enable")) {
      const bs = Number(parsed.battery_stop ?? 110);
      const bt = Number(parsed.bypass_temp ?? 110);
      const sched = Array.isArray(parsed.bypass_schedule) ? parsed.bypass_schedule : [];
      parsed.bypass_enable = bs <= 100 || bt <= 100 || sched.length > 0 ? 1 : 0;
    }
    return sanitizeCurrentConfig({
      ...CURRENT_DEFAULTS,
      ...parsed,
    }).value;
  } catch {
    return {
      ...CURRENT_DEFAULTS,
      battery_current: [...CURRENT_DEFAULTS.battery_current],
      restricted: [...CURRENT_DEFAULTS.restricted],
      app_list: [...CURRENT_DEFAULTS.app_list],
    };
  }
}

export async function saveCurrentJsonc(
  obj: CurrentConfig,
): Promise<{ ok: boolean; fixed: boolean; value: CurrentConfig }> {
  const { value, fixed } = sanitizeCurrentConfig(obj);
  const json = JSON.stringify(value, null, 2);
  const b64 = btoa(unescape(encodeURIComponent(json)));
  const result = await exec(
    `echo '${b64}' | base64 -d > '${PATHS.CURRENT_CONF}' 2>/dev/null || echo '${b64}' | base64 --decode > '${PATHS.CURRENT_CONF}' 2>/dev/null`,
  );
  return { ok: result.errno === 0, fixed, value };
}

export type { DeviceProfileExport } from "./deviceProfile";

export interface ConfigBundle {
  version: 1;
  settings: Settings;
  power_switches: string[];
  power_stop_schedule: string[];
  current?: CurrentConfig | null;
  device_profile?: DeviceProfileExport | null;
}

export interface NamedProfile extends ConfigBundle {
  id: string;
  name: string;
}

export {
  loadDeviceProfileExport,
  applyDeviceProfileExport,
  savePreferredSwitch,
  clearPreferredSwitch,
} from "./deviceProfile";

export {
  loadSwitchTestSummary,
  runTestSwitch,
  getSwitchTestStatus,
  waitSwitchTestDone,
} from "./switchTest";

export async function loadProfiles(): Promise<NamedProfile[]> {
  const result = await exec(`cat '${PATHS.PROFILES}' 2>/dev/null`);
  if (!result.stdout.trim()) return [];
  try {
    const parsed = JSON.parse(result.stdout) as { profiles?: NamedProfile[] };
    const list = Array.isArray(parsed.profiles) ? parsed.profiles : [];
    return list
      .filter((p) => p && typeof p.name === "string" && p.settings)
      .map((p) => ({
        ...p,
        id: String(p.id || p.name),
        version: 1 as const,
        power_switches: Array.isArray(p.power_switches) ? p.power_switches : [],
        power_stop_schedule: sanitizePowerStopSchedule(p.power_stop_schedule),
        device_profile: p.device_profile ?? null,
      }));
  } catch {
    return [];
  }
}

export async function saveProfiles(profiles: NamedProfile[]): Promise<boolean> {
  const json = JSON.stringify({ profiles }, null, 2);
  const b64 = btoa(unescape(encodeURIComponent(json)));
  const result = await exec(
    `echo '${b64}' | base64 -d > '${PATHS.PROFILES}' 2>/dev/null || echo '${b64}' | base64 --decode > '${PATHS.PROFILES}' 2>/dev/null`,
  );
  return result.errno === 0;
}

export async function exportConfigBundle(
  bundle: ConfigBundle,
  dest = "/sdcard/Download/qsc_battery_config.json",
): Promise<boolean> {
  const json = JSON.stringify(bundle, null, 2);
  const b64 = btoa(unescape(encodeURIComponent(json)));
  const safeDest = dest.replace(/'/g, "");
  const result = await exec(
    `mkdir -p "$(dirname '${safeDest}')" 2>/dev/null; echo '${b64}' | base64 -d > '${safeDest}' 2>/dev/null || echo '${b64}' | base64 --decode > '${safeDest}' 2>/dev/null`,
  );
  return result.errno === 0;
}

export async function importConfigBundle(
  src = "/sdcard/Download/qsc_battery_config.json",
): Promise<ConfigBundle | null> {
  const safeSrc = src.replace(/'/g, "");
  const result = await exec(`cat '${safeSrc}' 2>/dev/null`);
  if (!result.stdout.trim()) return null;
  try {
    const parsed = JSON.parse(result.stdout) as Partial<ConfigBundle>;
    if (!parsed.settings) return null;
    return {
      version: 1,
      settings: parsed.settings as Settings,
      power_switches: Array.isArray(parsed.power_switches) ? parsed.power_switches : [],
      power_stop_schedule: sanitizePowerStopSchedule(parsed.power_stop_schedule),
      current: parsed.current ?? null,
      device_profile: parsed.device_profile ?? null,
    };
  } catch {
    return null;
  }
}

export async function clearSwitchCache(): Promise<boolean> {
  const result = await exec(
    `rm -f '${PATHS.LIST_SWITCH}' '${PATHS.DEVICE_PROFILE}' '${PATHS.DATADIR}/active_switch' '${PATHS.NO_NODE_LOGGED}' '${PATHS.STOP_FAIL_HINT}' 2>/dev/null; echo 1`,
  );
  return result.stdout.trim() === "1";
}

/** 详细排障日志：data/debug_on，模块约 2s 内实时生效 */
export async function isDebugOn(): Promise<boolean> {
  const result = await exec(`[ -f '${PATHS.DEBUG_ON}' ] && echo 1 || echo 0`);
  return result.stdout.trim() === "1";
}

export async function setDebugOn(enabled: boolean): Promise<boolean> {
  const result = await exec(
    enabled
      ? `mkdir -p '${PATHS.DATADIR}' 2>/dev/null; : >'${PATHS.DEBUG_ON}' 2>/dev/null; [ -f '${PATHS.DEBUG_ON}' ] && echo 1 || echo 0`
      : `rm -f '${PATHS.DEBUG_ON}' 2>/dev/null; [ ! -f '${PATHS.DEBUG_ON}' ] && echo 1 || echo 0`,
  );
  return result.stdout.trim() === "1";
}
