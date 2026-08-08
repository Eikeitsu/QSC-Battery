import { CURRENT_DEFAULTS, DEFAULTS } from "@/shared/config/defaults";
import type { CurrentConfig, Settings } from "@/shared/types";

/** 统一数值范围（前后端口径一致） */
export const LIMITS = {
  levelMin: 1,
  levelMax: 100,
  levelOff: 110,
  powerStopTimeMin: 1,
  powerStopTimeMax: 120,
  tempSwitchMin: 25,
  tempSwitchMax: 70,
  currentTempMin: 25,
  currentTempMax: 60,
  safetyTempMin: 40,
  safetyTempMax: 55,
  /** 微安：0.1A–10A */
  uaMin: 100_000,
  uaMax: 10_000_000,
  /** 二限/游戏等小电流上限 3A */
  uaSmallMax: 3_000_000,
  appListMax: 64,
  scheduleMax: 16,
  pathListMax: 32,
};

export function clampInt(n: unknown, min: number, max: number, fallback: number): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  return Math.min(max, Math.max(min, Math.round(v)));
}

/** 1–100 有效阈值，或 110=关闭 */
export function clampLevelOrOff(n: unknown, fallback: number = LIMITS.levelOff): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  const r = Math.round(v);
  if (r === LIMITS.levelOff) return LIMITS.levelOff;
  if (r < LIMITS.levelMin || r > LIMITS.levelMax) return fallback;
  return r;
}

export function clampUa(
  n: unknown,
  fallback: number,
  max: number = LIMITS.uaMax,
  min: number = LIMITS.uaMin,
): number {
  return clampInt(n, min, max, fallback);
}

const PKG_RE = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/;
const SCHED_RE = /^([01]?\d|2[0-3]):([0-5]\d)-([01]?\d|2[0-3]):([0-5]\d)$/;
const DENY_NODE = new Set([
  "charge_control_limit",
  "thermal_input_current",
  "charge_current",
  "current_now",
  "voltage_now",
  "status",
  "capacity",
  "temp",
  "type",
  "uevent",
]);

function sanitizePackageList(list: unknown): string[] {
  const raw = Array.isArray(list) ? list : [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    const pkg = String(item || "").trim();
    if (!pkg || pkg.length > 128 || !PKG_RE.test(pkg)) continue;
    if (seen.has(pkg)) continue;
    seen.add(pkg);
    out.push(pkg);
    if (out.length >= LIMITS.appListMax) break;
  }
  return out;
}

function sanitizeScheduleList(list: unknown): string[] {
  const raw = Array.isArray(list) ? list : [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    const s = String(item || "").trim();
    if (!SCHED_RE.test(s) || seen.has(s)) continue;
    seen.add(s);
    out.push(s);
    if (out.length >= LIMITS.scheduleMax) break;
  }
  return out;
}

function sanitizeSysPaths(list: unknown, fallback: string[]): string[] {
  const raw = Array.isArray(list) ? list : [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    const p = String(item || "").trim();
    if (!p.startsWith("/sys/") && !p.startsWith("/proc/")) continue;
    if (p.length > 256 || p.includes("..") || /\s/.test(p)) continue;
    const base = p.slice(p.lastIndexOf("/") + 1);
    if (DENY_NODE.has(base)) continue;
    if (seen.has(p)) continue;
    seen.add(p);
    out.push(p);
    if (out.length >= LIMITS.pathListMax) break;
  }
  return out.length ? out : [...fallback];
}

function sanitizeRestricted(list: unknown, fallback: string[]): string[] {
  const raw = Array.isArray(list) ? list : [];
  const out: string[] = [];
  for (const item of raw) {
    const line = String(item || "").trim();
    if (!line || line.length > 320) continue;
    const m = line.match(/^(\/sys\/\S+)\s+value=([0-9A-Za-z:_-]{1,32})$/);
    if (!m) continue;
    out.push(`${m[1]} value=${m[2]}`);
    if (out.length >= LIMITS.pathListMax) break;
  }
  return out.length ? out : [...fallback];
}

export type SanitizeResult<T> = { value: T; fixed: boolean };

/** 停充/温控 conf 字段 */
export function sanitizeSettings(input: Settings): SanitizeResult<Settings> {
  const next: Settings = { ...input };
  let fixed = false;

  const mark = (cond: boolean) => {
    if (cond) fixed = true;
  };

  const powerStop = clampLevelOrOff(next.power_stop, Number(DEFAULTS.power_stop));
  if (String(powerStop) !== String(next.power_stop)) mark(true);
  next.power_stop = String(powerStop);

  let powerStart = clampInt(
    next.power_start,
    LIMITS.levelMin,
    LIMITS.levelMax,
    Number(DEFAULTS.power_start),
  );
  if (powerStop !== LIMITS.levelOff && powerStart >= powerStop) {
    powerStart = Math.max(LIMITS.levelMin, powerStop - 5);
    mark(true);
  }
  if (String(powerStart) !== String(input.power_start)) mark(true);
  next.power_start = String(powerStart);

  const stopTime = clampInt(
    next.power_stop_time,
    LIMITS.powerStopTimeMin,
    LIMITS.powerStopTimeMax,
    Number(DEFAULTS.power_stop_time),
  );
  if (String(stopTime) !== String(input.power_stop_time)) mark(true);
  next.power_stop_time = String(stopTime);

  next.charge_full = next.charge_full === "1" ? "1" : "0";
  next.power_reset = next.power_reset === "1" ? "1" : "0";
  next.Compatibility_mode = next.Compatibility_mode === "1" ? "1" : "0";
  next.temperature_switch = next.temperature_switch === "0" ? "0" : "1";

  const tempStop = clampInt(
    next.temperature_switch_stop,
    LIMITS.tempSwitchMin,
    LIMITS.tempSwitchMax,
    Number(DEFAULTS.temperature_switch_stop),
  );
  let tempStart = clampInt(
    next.temperature_switch_start,
    LIMITS.tempSwitchMin,
    LIMITS.tempSwitchMax,
    Number(DEFAULTS.temperature_switch_start),
  );
  if (tempStop <= tempStart) {
    tempStart = Math.max(LIMITS.tempSwitchMin, tempStop - 5);
    mark(true);
  }
  if (String(tempStop) !== String(input.temperature_switch_stop)) mark(true);
  if (String(tempStart) !== String(input.temperature_switch_start)) mark(true);
  next.temperature_switch_stop = String(tempStop);
  next.temperature_switch_start = String(tempStart);

  return { value: next, fixed };
}

/** current.json 全量规范化 */
export function sanitizeCurrentConfig(
  input: CurrentConfig,
): SanitizeResult<CurrentConfig> {
  const d = CURRENT_DEFAULTS;
  let fixed = false;
  const mark = (cond: boolean) => {
    if (cond) fixed = true;
  };

  const battery_stop = clampLevelOrOff(input.battery_stop, d.battery_stop);
  const bypass_temp = clampLevelOrOff(input.bypass_temp, d.bypass_temp);
  const slow_charge = clampLevelOrOff(input.slow_charge, d.slow_charge);
  mark(battery_stop !== Number(input.battery_stop));
  mark(bypass_temp !== Number(input.bypass_temp));
  mark(slow_charge !== Number(input.slow_charge));

  const defMax = clampUa(input.default_current_max, d.default_current_max);
  let cur1 = clampUa(input.default_current_max_limit, d.default_current_max_limit);
  let cur2 = clampUa(
    input.constant_current_max,
    d.constant_current_max,
    LIMITS.uaSmallMax,
  );
  let appCur = clampUa(input.app_current_max, d.app_current_max, LIMITS.uaSmallMax);
  mark(defMax !== Number(input.default_current_max));
  mark(cur1 !== Number(input.default_current_max_limit));
  mark(cur2 !== Number(input.constant_current_max));
  mark(appCur !== Number(input.app_current_max));

  // 层级：二限 ≤ 游戏 ≤ 一限 ≤ 默认上限
  if (cur1 > defMax) {
    cur1 = defMax;
    mark(true);
  }
  if (appCur > cur1) {
    appCur = cur1;
    mark(true);
  }
  if (cur2 > appCur) {
    cur2 = appCur;
    mark(true);
  }

  const limit1 = clampInt(
    input.default_current_limit,
    LIMITS.currentTempMin,
    LIMITS.currentTempMax,
    d.default_current_limit,
  );
  let limit2 = clampInt(
    input.temperature_current_limit,
    LIMITS.currentTempMin,
    LIMITS.currentTempMax,
    d.temperature_current_limit,
  );
  if (limit2 <= limit1) {
    limit2 = Math.min(LIMITS.currentTempMax, limit1 + 5);
    mark(true);
  }
  mark(limit1 !== Number(input.default_current_limit));
  mark(limit2 !== Number(input.temperature_current_limit));

  const safety = clampInt(
    input.safety_temp_max,
    LIMITS.safetyTempMin,
    LIMITS.safetyTempMax,
    d.safety_temp_max,
  );
  mark(safety !== Number(input.safety_temp_max));

  const app_list = sanitizePackageList(input.app_list);
  const bypass_schedule = sanitizeScheduleList(input.bypass_schedule);
  const battery_current = sanitizeSysPaths(
    input.battery_current,
    d.battery_current as string[],
  );
  const restricted = sanitizeRestricted(input.restricted, d.restricted as string[]);
  if (app_list.length !== (input.app_list?.length || 0)) mark(true);
  if (bypass_schedule.length !== (input.bypass_schedule?.length || 0)) mark(true);

  return {
    fixed,
    value: {
      current_control: Number(input.current_control) ? 1 : 0,
      bypass_enable: Number(input.bypass_enable) ? 1 : 0,
      battery_stop,
      bypass_temp,
      bypass_schedule,
      slow_charge,
      default_current_max: defMax,
      temperature_current: Number(input.temperature_current) ? 1 : 0,
      default_current_limit: limit1,
      default_current_max_limit: cur1,
      temperature_current_limit: limit2,
      constant_current_max: cur2,
      app_limit: Number(input.app_limit) ? 1 : 0,
      app_current_max: appCur,
      app_list,
      bypass_mode: input.bypass_mode === "auto" ? "auto" : "sim",
      safety_temp_max: safety,
      battery_current,
      restricted,
    },
  };
}

/** 自定义毫安输入 → 合法微安；非法返回 null */
export function parseMaToUa(
  maText: string,
  maxUa = LIMITS.uaMax,
  minUa = LIMITS.uaMin,
): number | null {
  const ma = Number(String(maText ?? "").trim());
  if (!Number.isFinite(ma) || ma < 0) return null;
  const ua = Math.round(ma * 1000);
  if (ua < minUa || ua > maxUa) return null;
  return ua;
}
