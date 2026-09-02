import { PATHS } from "@/shared/config/paths";
import { exec } from "./index";

export type ChargeEventType =
  | "PLUG"
  | "UNPLUG"
  | "CHARGE_START"
  | "CHARGE_STOP"
  | "MAINTAIN"
  | "HEALTH"
  | "THERMAL"
  | "WARNING"
  | "CUSTOM";

export interface ChargeEvent {
  ts: number;
  dateText: string;
  timeText: string;
  type: ChargeEventType;
  level: number | null;
  temp: number | null;
  detail: string;
  raw: string;
}

const EVENT_RE =
  /^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+\[EVENT\]\s+([A-Z_]+)\s+(\d+|--)%\s+(\d+|--|-\d+)°C\s*(.*)$/;

function parseChargeEventsText(text: string): ChargeEvent[] {
  const raw = String(text || "").trim();
  if (!raw) return [];
  const out: ChargeEvent[] = [];
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(EVENT_RE);
    if (!m) continue;
    const [, d, t, type, level, temp, detail] = m;
    const dt = new Date(`${d}T${t}`);
    const ts = Number.isFinite(dt.getTime()) ? Math.floor(dt.getTime() / 1000) : 0;
    out.push({
      ts,
      dateText: d ?? "",
      timeText: t ?? "",
      type: type as ChargeEventType,
      level: level && level !== "--" ? Number(level) : null,
      temp: temp && temp !== "--" ? Number(temp) : null,
      detail: detail || "",
      raw: line,
    });
  }
  return out.sort((a, b) => a.ts - b.ts);
}

export async function loadChargeEvents(maxLines = 80): Promise<ChargeEvent[]> {
  const result = await exec(
    `{ [ -f '${PATHS.CHARGE_EVENTS}' ] && tail -n ${maxLines} '${PATHS.CHARGE_EVENTS}' 2>/dev/null; }`,
  );
  return parseChargeEventsText(result.stdout);
}
