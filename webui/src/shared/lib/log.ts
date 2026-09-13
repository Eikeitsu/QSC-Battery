import { LogLevel, isLogLevel } from "@/shared/config/enums";

const LEVEL_TAG = /\[(INFO|WARN|ERROR|DEBUG)\]/i;
const EMPTY_HINTS = new Set(["", "暂无日志", "暂无日志（触发功能后才会写入）"]);
/** 一轮停充的起点（含温控停充 / App 停充） */
const STOP_RE = /停止充电|按\s*App\s*停充/;
/** 一轮停充的结束（恢复充电，或拔线/关模块时清除停充状态） */
const RESUME_RE = /恢复充电|清除停充状态/;

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

/** 停充/恢复边界行：会话分组时始终保留，不受等级筛选影响 */
export function isSessionBoundaryLine(raw: string): boolean {
  return STOP_RE.test(raw) || RESUME_RE.test(raw);
}

/**
 * 会话模式用：先全量 groupLogSessions，再按等级滤行。
 * 边界行（停充/恢复）始终保留，避免 Info 筛选把会话拆碎。
 */
export function filterLogSessions(sessions: LogSession[], level: string): LogSession[] {
  if (!level) return sessions;
  return sessions
    .map((session) => {
      const entries = session.entries.filter(
        (e) => e.level === level || isSessionBoundaryLine(e.raw),
      );
      if (!entries.length) return null;
      return {
        ...session,
        entries,
        hasError: entries.some((e) => e.level === LogLevel.Error),
        hasWarn: entries.some((e) => e.level === LogLevel.Warn),
      };
    })
    .filter((s): s is LogSession => s !== null);
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

function stopTitle(session: LogSession): string {
  const stop = session.entries.find((x) => STOP_RE.test(x.raw));
  return shortTitle(stop?.raw || session.title) || "停充";
}

/** 按「停充 → 恢复/清除」折叠为一轮会话；最新在前。停充前的杂项单独成组，不并入首轮停充。 */
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
        entries: [e],
      };
      bumpFlags(current, e);
      continue;
    }
    if (RESUME_RE.test(e.raw) && current) {
      current.entries.push(e);
      bumpFlags(current, e);
      current.open = false;
      current.title = `${stopTitle(current)} → 已恢复`;
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

  const latestFirst = sessions.reverse();
  if (orphan.length) {
    latestFirst.push({
      id: "orphan",
      title: "其它日志",
      open: false,
      hasError: orphan.some((x) => x.level === LogLevel.Error),
      hasWarn: orphan.some((x) => x.level === LogLevel.Warn),
      entries: orphan,
    });
  }
  return latestFirst;
}
