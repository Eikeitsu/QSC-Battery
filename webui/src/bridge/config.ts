import { CURRENT_DEFAULTS } from "../shared/defaults";
import { PATHS } from "../shared/paths";
import { sanitizeCurrentConfig } from "../shared/limits";
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
  const safeVal = String(value).replace(/[^0-9A-Za-z._:-]/g, "");
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
    // 旧配置无 bypass_enable：已配置触发条件则视为开启，否则关
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
