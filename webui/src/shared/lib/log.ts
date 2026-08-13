import { LogLevel, isLogLevel } from "@/shared/config/enums";

const LEVEL_TAG = /\[(INFO|WARN|ERROR|DEBUG)\]/i;
const EMPTY_HINTS = new Set(["", "暂无日志", "暂无日志（触发功能后才会写入）"]);

export interface LogEntry {
  raw: string;
  level: LogLevel;
}

export function parseLogLevel(line: string): LogLevel {
  const m = line.match(LEVEL_TAG);
  if (!m) return LogLevel.Info;
  const v = m[1].toLowerCase();
  return isLogLevel(v) ? v : LogLevel.Info;
}

export function parseLogText(text: string): LogEntry[] {
  const raw = String(text || "").trim();
  if (EMPTY_HINTS.has(raw)) return [];
  return raw
    .split("\n")
    .map((line) => line.trimEnd())
    .filter(Boolean)
    .map((line) => ({ raw: line, level: parseLogLevel(line) }));
}

export function filterLogEntries(entries: LogEntry[], level: string): LogEntry[] {
  if (!level) return entries;
  return entries.filter((e) => e.level === level);
}
