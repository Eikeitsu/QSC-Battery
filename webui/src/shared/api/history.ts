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
    `tail -n ${maxPoints + 1} '${PATHS.CHARGE_HISTORY}' 2>/dev/null`,
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

export async function loadCompatHint(): Promise<string> {
  const result = await exec(`cat '${PATHS.COMPAT_HINT}' 2>/dev/null`);
  return result.stdout.trim();
}
