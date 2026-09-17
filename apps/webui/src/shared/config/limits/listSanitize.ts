import { LIMITS } from "./constants";

export const PKG_RE = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/;
export const SCHED_RE = /^([01]?\d|2[0-3]):([0-5]\d)-([01]?\d|2[0-3]):([0-5]\d)$/;

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

export function sanitizePackageList(list: unknown): string[] {
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

export function sanitizeScheduleList(list: unknown): string[] {
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

/** 电量停充时段 HH:MM-HH:MM */
export function sanitizePowerStopSchedule(list: unknown): string[] {
  return sanitizeScheduleList(list);
}

export function sanitizeSysPaths(list: unknown, fallback: string[]): string[] {
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

export function sanitizeRestricted(list: unknown, fallback: string[]): string[] {
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
