import { PATHS } from "@/shared/config/paths";
import { exec } from "./ksu";

export interface HistoryPoint {
  ts: number;
  level: number;
  temp: number | null;
  currentUa: number | null;
  status: string;
  source: string;
}

export async function loadChargeHistory(maxPoints = 240): Promise<HistoryPoint[]> {
  const result = await exec(
    `{ cat '${PATHS.CHARGE_HISTORY}' 2>/dev/null; cat '${PATHS.CHARGE_HISTORY}.pending' 2>/dev/null; } | tail -n ${maxPoints + 1}`,
  );
  const text = result.stdout.trim();
  if (!text) return [];
  const lines = text.split(/\r?\n/).filter(Boolean);
  const out: HistoryPoint[] = [];
  for (const line of lines) {
    if (line.startsWith("ts,")) continue;
    const parts = line.split(",");
    if (parts.length < 2) continue;
    const ts = Number(parts[0]);
    const level = Number(parts[1]);
    if (!Number.isFinite(ts) || !Number.isFinite(level)) continue;
    const tempRaw = parts[2];
    const curRaw = parts[3];
    const temp = tempRaw && tempRaw !== "--" ? Number(tempRaw) : null;
    const currentUa = curRaw ? Number(curRaw) : null;
    out.push({
      ts,
      level,
      temp: Number.isFinite(temp as number) ? (temp as number) : null,
      currentUa: Number.isFinite(currentUa as number) ? (currentUa as number) : null,
      status: parts[4] || "",
      source: parts[5] || "",
    });
  }
  return out;
}

/** +1d2h3m4s567ms → 毫秒；解析失败返回 null */
function parseHistoryOffset(token: string): number | null {
  if (token === "0") return 0;
  const m = token.match(
    /^\+?(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m(?!s))?(?:(\d+)s)?(?:(\d+)ms)?$/,
  );
  if (!m) return null;
  const [, d, h, min, s, ms] = m;
  if (!d && !h && !min && !s && !ms) return null;
  return (
    Number(d || 0) * 86_400_000 +
    Number(h || 0) * 3_600_000 +
    Number(min || 0) * 60_000 +
    Number(s || 0) * 1000 +
    Number(ms || 0)
  );
}

/** RESET:TIME: 2026-08-27-10-21-56 → epoch 秒（本地时区） */
function parseResetTime(text: string): number | null {
  const m = text.match(/RESET:TIME:\s*(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})/);
  if (!m) return null;
  const [, y, mo, d, h, mi, s] = m.map(Number) as unknown as number[];
  const t = new Date(y, mo - 1, d, h, mi, s).getTime();
  return Number.isFinite(t) ? Math.floor(t / 1000) : null;
}

/**
 * 系统自带的 batterystats 历史：电量 / 温度 / 插电状态。
 * 这份记录系统本来就在写，读取它不产生额外后台采样与写盘；
 * 代价是没有充电电流（系统不记该字段），故仅用于补齐放电段。
 */
export async function loadSystemBatteryHistory(): Promise<HistoryPoint[]> {
  let text = "";
  const primary = await exec(
    "dumpsys batterystats --history 2>/dev/null | grep -E 'RESET:TIME|^ *[+0]' | tail -n 1200",
  );
  text = primary.stdout.trim();
  if (!text) {
    const fallback = await exec(
      "dumpsys batterystats 2>/dev/null | sed -n '/Battery History/,/^$/p' | tail -n 1200",
    );
    text = fallback.stdout.trim();
  }
  return parseBatteryStatsHistory(text);
}

export function parseBatteryStatsHistory(text: string): HistoryPoint[] {
  if (!text.trim()) return [];
  const out: HistoryPoint[] = [];
  let baseSec: number | null = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    const reset = parseResetTime(line);
    if (reset != null) {
      baseSec = reset;
      continue;
    }
    if (baseSec == null) continue;
    // 形如：+1m30s123ms (2) 099 c0900422 status=discharging temp=305 volt=4167
    const m = line.match(/^(\+?[\dhmsd]+|0)\s+\(\d+\)\s+(\d{1,3})\b(.*)$/);
    if (!m) continue;
    const offset = parseHistoryOffset(m[1]);
    if (offset == null) continue;
    const level = Number(m[2]);
    if (!Number.isFinite(level) || level < 0 || level > 100) continue;
    const rest = m[3];
    const tempRaw = rest.match(/\btemp=(\d+)/);
    const plug = rest.match(/\bplug=(\w+)/);
    const status = rest.match(/\bstatus=(\w+)/);
    out.push({
      ts: baseSec + Math.floor(offset / 1000),
      level,
      // batterystats 的 temp 单位是 0.1°C
      temp: tempRaw ? Math.round(Number(tempRaw[1]) / 10) : null,
      currentUa: null,
      status: status ? status[1] : "",
      source: plug && plug[1] !== "none" ? plug[1] : "none",
    });
  }
  return out;
}

/** 模块采样（含电流）优先，其余时间段用系统记录补齐 */
export function mergeHistory(
  sampled: HistoryPoint[],
  system: HistoryPoint[],
): HistoryPoint[] {
  if (!system.length) return sampled;
  const covered = new Set(sampled.map((p) => Math.round(p.ts / 60)));
  const merged = [
    ...sampled,
    ...system.filter((p) => !covered.has(Math.round(p.ts / 60))),
  ];
  return merged.sort((a, b) => a.ts - b.ts);
}

export async function loadCompatHint(): Promise<string> {
  const result = await exec(`cat '${PATHS.COMPAT_HINT}' 2>/dev/null`);
  return result.stdout.trim();
}
