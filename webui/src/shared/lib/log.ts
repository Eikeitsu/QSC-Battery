import { LogLevel, isLogLevel } from "@/shared/config/enums";

const LEVEL_TAG = /\[(INFO|WARN|ERROR|DEBUG)\]/i;
const EMPTY_HINTS = new Set(["", "暂无日志", "暂无日志（触发功能后才会写入）"]);
/** 一轮停充的起点（含温控停充 / App 停充） */
const STOP_RE = /停止充电|按\s*App\s*停充/;
/** 一轮停充的结束（恢复充电，或拔线/关模块时清除停充状态） */
const RESUME_RE = /恢复充电|清除停充状态/;
const TS_RE = /^(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}):\d{2}\s*/;

export interface LogEntry {
  raw: string;
  level: LogLevel;
  /**
   * 会话筛选时：等级与筛选不一致，但是停充/恢复边界，作弱化「上下文」展示。
   * 平铺模式不使用。
   */
  context?: boolean;
}

export interface LogSession {
  id: string;
  title: string;
  /** 仍在停充、未见恢复 */
  open: boolean;
  hasError: boolean;
  hasWarn: boolean;
  /** 状态 + 事件标签；首项为 停充中 / 已恢复 / 杂项 */
  badges: string[];
  entries: LogEntry[];
}

export function parseLogLevel(line: string): LogLevel {
  const m = line.match(LEVEL_TAG);
  if (!m) return LogLevel.Info;
  const v = m[1]!.toLowerCase();
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

/** 停充/恢复边界行 */
export function isSessionBoundaryLine(raw: string): boolean {
  return STOP_RE.test(raw) || RESUME_RE.test(raw);
}

/**
 * 会话模式：先全量 groupLogSessions，再按等级滤行。
 * - 匹配行：level === filter
 * - 上下文边界：停充/恢复且等级不匹配 → 保留并标记 context（弱化展示）
 * - 无任何匹配行的会话丢弃（仅剩上下文也不保留）
 */
export function filterLogSessions(sessions: LogSession[], level: string): LogSession[] {
  if (!level) {
    return sessions.map((s) => ({
      ...s,
      entries: s.entries.map((e) => (e.context ? { raw: e.raw, level: e.level } : e)),
    }));
  }
  return sessions
    .map((session) => {
      const entries: LogEntry[] = [];
      let hasMatch = false;
      for (const e of session.entries) {
        if (e.level === level) {
          entries.push({ raw: e.raw, level: e.level, context: false });
          hasMatch = true;
        } else if (isSessionBoundaryLine(e.raw)) {
          entries.push({ raw: e.raw, level: e.level, context: true });
        }
      }
      if (!hasMatch) return null;
      const next: LogSession = {
        ...session,
        entries,
        hasError: entries.some((e) => !e.context && e.level === LogLevel.Error),
        hasWarn: entries.some((e) => !e.context && e.level === LogLevel.Warn),
        badges: [],
      };
      next.badges = deriveSessionBadges(next);
      return next;
    })
    .filter((s): s is LogSession => s !== null);
}

function extractClock(raw: string): string {
  const m = TS_RE.exec(raw);
  return m?.[2] || "";
}

function shortTitle(raw: string): string {
  return raw
    .replace(TS_RE, "")
    .replace(/\[(INFO|WARN|ERROR|DEBUG)\]\s*/i, "")
    .trim()
    .slice(0, 72);
}

function briefReason(raw: string): string {
  return shortTitle(raw).slice(0, 48);
}

function resumeLabel(raw: string): string {
  return /清除停充/.test(raw) ? "清除" : "恢复";
}

function bumpFlags(session: LogSession, e: LogEntry) {
  if (e.level === LogLevel.Error) session.hasError = true;
  if (e.level === LogLevel.Warn) session.hasWarn = true;
}

/** 时间线标题：`10:01 …停止充电 → 10:05 恢复` / `· 停充中` */
export function formatSessionTitle(
  entries: LogEntry[],
  open: boolean,
  orphan = false,
): string {
  if (orphan) return "其它日志";
  const stop = entries.find((x) => STOP_RE.test(x.raw));
  const resume = entries.find((x) => RESUME_RE.test(x.raw));
  const stopClock = stop ? extractClock(stop.raw) : "";
  const stopBrief = stop ? briefReason(stop.raw) : "停充";
  const head = [stopClock, stopBrief].filter(Boolean).join(" ");
  if (open || !resume) {
    return `${head} · 停充中`;
  }
  const resumeClock = extractClock(resume.raw);
  const tail = [resumeClock, resumeLabel(resume.raw)].filter(Boolean).join(" ");
  return `${head} → ${tail}`;
}

/**
 * 会话标签：首项固定为 停充中 / 已恢复 / 杂项，其后按日志事件追加。
 * 不拆会话，只丰富卡片上的可见标签。
 */
export function deriveSessionBadges(
  session: Pick<LogSession, "id" | "open" | "hasError" | "hasWarn" | "entries">,
): string[] {
  const badges: string[] = [];
  if (session.id === "orphan") badges.push("杂项");
  else if (session.open) badges.push("停充中");
  else badges.push("已恢复");

  if (session.id === "orphan") {
    if (session.hasError) badges.push("有错误");
    else if (session.hasWarn) badges.push("有警告");
    return badges;
  }

  const blob = session.entries.map((e) => e.raw).join("\n");

  if (/触发开关温控：停止充电/.test(blob)) badges.push("温控停充");
  else if (/按\s*App\s*停充/.test(blob)) badges.push("App停充");
  else if (STOP_RE.test(blob)) badges.push("电量停充");

  if (/强制恢复充电|忽略温控\/应用停充/.test(blob)) badges.push("强制恢复");
  else if (/清除停充状态/.test(blob)) badges.push("拔线清除");
  else if (/模块已关闭/.test(blob)) badges.push("模块关闭");
  else if (/触发开关温控：恢复充电/.test(blob)) badges.push("温控恢复");

  if (session.hasError) badges.push("有错误");
  else if (session.hasWarn) badges.push("有警告");

  return badges;
}

/** 按「停充 → 恢复/清除」折叠为一轮会话；最新在前。停充前的其它日志单独成组。 */
export function groupLogSessions(entries: LogEntry[]): LogSession[] {
  const sessions: LogSession[] = [];
  let current: LogSession | null = null;
  const orphan: LogEntry[] = [];

  const pushCurrent = () => {
    if (current) {
      current.title = formatSessionTitle(current.entries, current.open, false);
      current.badges = deriveSessionBadges(current);
      sessions.push(current);
      current = null;
    }
  };

  for (const e of entries) {
    if (STOP_RE.test(e.raw)) {
      pushCurrent();
      current = {
        id: `s${sessions.length}-${e.raw.length}`,
        title: "",
        open: true,
        hasError: false,
        hasWarn: false,
        badges: [],
        entries: [e],
      };
      bumpFlags(current, e);
      continue;
    }
    if (RESUME_RE.test(e.raw) && current) {
      current.entries.push(e);
      bumpFlags(current, e);
      current.open = false;
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
    const orphanSession: LogSession = {
      id: "orphan",
      title: formatSessionTitle(orphan, false, true),
      open: false,
      hasError: orphan.some((x) => x.level === LogLevel.Error),
      hasWarn: orphan.some((x) => x.level === LogLevel.Warn),
      badges: [],
      entries: orphan,
    };
    orphanSession.badges = deriveSessionBadges(orphanSession);
    latestFirst.push(orphanSession);
  }
  return latestFirst;
}
