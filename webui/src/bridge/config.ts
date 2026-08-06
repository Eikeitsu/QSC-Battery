import { CURRENT_DEFAULTS } from "../shared/defaults";
import { PATHS } from "../shared/paths";
import type { CurrentConfig } from "../shared/types";
import { exec } from "./ksu";

export async function getConf(key: string): Promise<string> {
  const result = await exec(
    `grep '^${key}=' '${PATHS.CONF}' 2>/dev/null | tail -1 | cut -d= -f2-`,
  );
  return result.stdout.trim();
}

export async function setConf(key: string, value: string | number): Promise<void> {
  const safeKey = String(key).replace(/[^a-zA-Z0-9_]/g, "");
  const safeVal = String(value).replace(/'/g, "");
  await exec(
    `sed -i '/^${safeKey}=/d' '${PATHS.CONF}' 2>/dev/null; echo '${safeKey}=${safeVal}' >> '${PATHS.CONF}'`,
  );
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
  return result.stdout.trim() === "1";
}

export function normalizeAppList(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.map((s) => String(s).trim()).filter(Boolean);
  }
  return String(value || "")
    .split(/\n+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

export function normalizeScheduleList(value: unknown): string[] {
  const raw = Array.isArray(value)
    ? value.map((s) => String(s).trim())
    : String(value || "")
        .split(/\n+/)
        .map((s) => s.trim());
  const re = /^([01]?\d|2[0-3]):([0-5]\d)-([01]?\d|2[0-3]):([0-5]\d)$/;
  return raw.filter((s) => re.test(s));
}

export async function loadCurrentJsonc(): Promise<CurrentConfig> {
  const result = await exec(`cat '${PATHS.CURRENT_CONF}' 2>/dev/null`);
  if (!result.stdout.trim()) return { ...CURRENT_DEFAULTS };
  try {
    const parsed = parseJsonc(result.stdout);
    const merged: CurrentConfig = {
      ...CURRENT_DEFAULTS,
      ...(parsed as Partial<CurrentConfig>),
    };
    merged.app_list = Array.isArray(merged.app_list)
      ? normalizeAppList(merged.app_list)
      : [...CURRENT_DEFAULTS.app_list];
    merged.bypass_schedule = normalizeScheduleList(merged.bypass_schedule);
    merged.battery_current =
      Array.isArray(merged.battery_current) && merged.battery_current.length > 0
        ? merged.battery_current
        : [...CURRENT_DEFAULTS.battery_current];
    merged.restricted = Array.isArray(merged.restricted)
      ? merged.restricted.filter((x): x is string => typeof x === "string")
      : [...CURRENT_DEFAULTS.restricted];
    merged.bypass_mode = merged.bypass_mode === "auto" ? "auto" : "sim";
    merged.bypass_temp = Number(merged.bypass_temp) || 110;
    return merged;
  } catch {
    return {
      ...CURRENT_DEFAULTS,
      battery_current: [...CURRENT_DEFAULTS.battery_current],
      restricted: [...CURRENT_DEFAULTS.restricted],
      app_list: [...CURRENT_DEFAULTS.app_list],
    };
  }
}

export async function saveCurrentJsonc(obj: CurrentConfig): Promise<boolean> {
  const batteryCurrent =
    Array.isArray(obj.battery_current) && obj.battery_current.length > 0
      ? obj.battery_current
      : [...CURRENT_DEFAULTS.battery_current];
  const payload: CurrentConfig = {
    current_control: Number(obj.current_control) ? 1 : 0,
    battery_stop: Number(obj.battery_stop) || 110,
    bypass_temp: Number(obj.bypass_temp) || 110,
    bypass_schedule: normalizeScheduleList(obj.bypass_schedule),
    slow_charge: Number(obj.slow_charge) || 110,
    default_current_max: Number(obj.default_current_max) || 5000000,
    temperature_current: Number(obj.temperature_current) ? 1 : 0,
    default_current_limit: Number(obj.default_current_limit) || 40,
    default_current_max_limit: Number(obj.default_current_max_limit) || 1500000,
    temperature_current_limit: Number(obj.temperature_current_limit) || 45,
    constant_current_max: Math.max(50000, Number(obj.constant_current_max) || 100000),
    app_limit: Number(obj.app_limit) ? 1 : 0,
    app_current_max: Math.max(50000, Number(obj.app_current_max) || 200000),
    app_list: normalizeAppList(obj.app_list),
    bypass_mode: obj.bypass_mode === "auto" ? "auto" : "sim",
    safety_temp_max: Math.min(55, Math.max(40, Number(obj.safety_temp_max) || 48)),
    battery_current: batteryCurrent,
    restricted: Array.isArray(obj.restricted)
      ? obj.restricted.filter((x): x is string => typeof x === "string")
      : [...CURRENT_DEFAULTS.restricted],
  };
  const json = JSON.stringify(payload, null, 2);
  const b64 = btoa(unescape(encodeURIComponent(json)));
  const result = await exec(
    `echo '${b64}' | base64 -d > '${PATHS.CURRENT_CONF}' 2>/dev/null || echo '${b64}' | base64 --decode > '${PATHS.CURRENT_CONF}' 2>/dev/null`,
  );
  return result.errno === 0;
}
