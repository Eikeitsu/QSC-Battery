import { LogLevel, isLogLevel } from "@/shared/config/enums";

const LEVEL_TAG = /\[(INFO|WARN|ERROR|DEBUG)\]/i;
const EMPTY_HINTS = new Set(["", "暂无日志", "暂无日志（触发功能后才会写入）"]);
const STOP_RE = /停止充电/;
const RESUME_RE = /恢复充电/;

export interface LogEntry {
  raw: string;
  level: LogLevel;
}

export interface LogSession {
  id: string;
  title: string;
  /** 仍在停充、未见恢复 */
  open: boolean;
  hasError: boolean;
  hasWarn: boolean;
  entries: LogEntry[];
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

function shortTitle(raw: string): string {
  return raw
    .replace(/^\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}\s*/, "")
    .replace(/\[(INFO|WARN|ERROR|DEBUG)\]\s*/i, "")
    .trim()
    .slice(0, 72);
}

function bumpFlags(session: LogSession, e: LogEntry) {
  if (e.level === LogLevel.Error) session.hasError = true;
  if (e.level === LogLevel.Warn) session.hasWarn = true;
}

/** 按「停止充电 → 恢复充电」折叠为一轮会话；最新在前 */
export function groupLogSessions(entries: LogEntry[]): LogSession[] {
  const sessions: LogSession[] = [];
  let current: LogSession | null = null;
  const orphan: LogEntry[] = [];

  const pushCurrent = () => {
    if (current) {
      sessions.push(current);
      current = null;
    }
  };

  for (const e of entries) {
    if (STOP_RE.test(e.raw)) {
      pushCurrent();
      current = {
        id: `s${sessions.length}-${e.raw.length}`,
        title: shortTitle(e.raw) || "停充",
        open: true,
        hasError: false,
        hasWarn: false,
        entries: orphan.length ? [...orphan.splice(0, orphan.length), e] : [e],
      };
      bumpFlags(current, e);
      continue;
    }
    if (RESUME_RE.test(e.raw) && current) {
      current.entries.push(e);
      bumpFlags(current, e);
      current.open = false;
      current.title = `${shortTitle(current.entries[0]?.raw || "")} → 已恢复`;
      pushCurrent();
      continue;
    }
    if (current) {
      current.entries.push(e);
      bumpFlags(current, e);
    } else {
      orphan.push(e);
    }
  }
  pushCurrent();
  if (orphan.length) {
    sessions.push({
      id: "orphan",
      title: "其它日志",
      open: false,
      hasError: orphan.some((x) => x.level === LogLevel.Error),
      hasWarn: orphan.some((x) => x.level === LogLevel.Warn),
      entries: orphan,
    });
  }
  return sessions.reverse();
}
