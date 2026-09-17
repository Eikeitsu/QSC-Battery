import { describe, expect, it } from "vitest";
import { LogLevel } from "@/shared/config/enums";
import {
  deriveSessionBadges,
  filterLogSessions,
  formatSessionTitle,
  groupLogSessions,
  parseLogText,
} from "@/shared/lib/log";

describe("parseLogText", () => {
  it("parses leveled lines", () => {
    const entries = parseLogText(
      "2026-08-26_10:00:00 [INFO] a\n2026-08-26_10:00:01 [WARN] b\n",
    );
    expect(entries).toHaveLength(2);
    expect(entries[0]!.level).toBe(LogLevel.Info);
    expect(entries[1]!.level).toBe(LogLevel.Warn);
  });

  it("treats empty hints as no entries", () => {
    expect(parseLogText("暂无日志")).toEqual([]);
  });
});

describe("groupLogSessions", () => {
  it("folds stop→resume with timeline title; latest open first", () => {
    const entries = parseLogText(
      [
        "2026-08-26_10:00:00 [INFO] boot",
        "2026-08-26_10:01:00 [INFO] 电量80 停止充电 [/sys/x]",
        "2026-08-26_10:01:03 [WARN] drift",
        "2026-08-26_10:05:00 [INFO] 电量75 恢复充电 [/sys/x]",
        "2026-08-26_11:00:00 [INFO] 电量90 停止充电 [/sys/y]",
      ].join("\n"),
    );
    const sessions = groupLogSessions(entries);
    expect(sessions).toHaveLength(3);
    expect(sessions[0]!.open).toBe(true);
    expect(sessions[0]!.outcome).toBe("ongoing");
    expect(sessions[0]!.title).toMatch(/11:00.*停止充电.*停充中/);
    expect(sessions[0]!.badges).toEqual(["停充中", "已停充", "电量停充"]);
    expect(sessions[0]!.entries.some((e) => /停止充电/.test(e.raw))).toBe(true);
    expect(sessions[1]!.open).toBe(false);
    expect(sessions[1]!.outcome).toBe("resumed");
    expect(sessions[1]!.entries).toHaveLength(3);
    expect(sessions[1]!.hasWarn).toBe(true);
    expect(sessions[1]!.badges).toEqual(["已恢复", "已停充", "电量停充", "有警告"]);
    expect(sessions[1]!.title).toMatch(/10:01.*停止充电.*→.*10:05.*恢复/);
    expect(sessions[2]!.id).toBe("orphan");
    expect(sessions[2]!.outcome).toBe("misc");
    expect(sessions[2]!.title).toBe("其它日志");
    expect(sessions[2]!.badges).toEqual(["杂项"]);
    expect(sessions[2]!.entries).toHaveLength(1);
  });

  it("treats App stop and unplug clear as 已拔线", () => {
    const entries = parseLogText(
      [
        "2026-08-26_12:00:00 [INFO] 电量88 按 App 停充 [/sys/x]",
        "2026-08-26_12:10:00 [INFO] 已拔出充电器，还原充电节点并清除停充状态 [/sys/x]",
      ].join("\n"),
    );
    const sessions = groupLogSessions(entries);
    expect(sessions).toHaveLength(1);
    expect(sessions[0]!.open).toBe(false);
    expect(sessions[0]!.outcome).toBe("unplugged");
    expect(sessions[0]!.title).toMatch(/12:00.*按 App 停充.*→.*12:10.*拔线/);
    expect(sessions[0]!.badges).toEqual(["已拔线", "已停充", "App停充", "拔线清除"]);
  });

  it("does not treat threshold hint as stop/resume", () => {
    const entries = parseLogText(
      "2026-08-26_09:00:00 [WARN] 电量阈值已纠正 100/95 → 停充100% 恢复95%\n",
    );
    const sessions = groupLogSessions(entries);
    expect(sessions).toHaveLength(1);
    expect(sessions[0]!.id).toBe("orphan");
  });
});

describe("formatSessionTitle", () => {
  it("builds open and closed titles", () => {
    const open = parseLogText("2026-08-26_10:01:00 [INFO] 电量80 停止充电 [/sys/x]");
    expect(formatSessionTitle(open, true)).toMatch(/10:01.*停止充电.*· 停充中/);
    const closed = parseLogText(
      [
        "2026-08-26_10:01:00 [INFO] 电量80 停止充电 [/sys/x]",
        "2026-08-26_10:05:00 [INFO] 电量75 恢复充电 [/sys/x]",
      ].join("\n"),
    );
    expect(formatSessionTitle(closed, false)).toMatch(/10:01.*→.*10:05 恢复/);
  });
});

describe("deriveSessionBadges", () => {
  it("keeps primary names and adds event tags", () => {
    const temp = groupLogSessions(
      parseLogText(
        [
          "2026-08-26_10:01:00 [INFO] 电量80 触发开关温控：停止充电 温度45 [/sys/x]",
          "2026-08-26_10:05:00 [INFO] 电量80 触发开关温控：恢复充电 温度38 [/sys/x]",
        ].join("\n"),
      ),
    )[0]!;
    expect(deriveSessionBadges(temp)).toEqual([
      "已恢复",
      "已停充",
      "温控停充",
      "温控恢复",
    ]);

    const forced = groupLogSessions(
      parseLogText(
        [
          "2026-08-26_10:01:00 [INFO] 电量80 触发开关温控：停止充电 温度45 [/sys/x]",
          "2026-08-26_10:05:00 [INFO] 电量14 已低于安全线 15%，忽略温控/应用停充，强制恢复充电",
        ].join("\n"),
      ),
    )[0]!;
    expect(deriveSessionBadges(forced)).toEqual([
      "已恢复",
      "已停充",
      "温控停充",
      "强制恢复",
    ]);
  });
});

describe("filterLogSessions", () => {
  it("keeps Info boundaries as matches when filtering Info", () => {
    const entries = parseLogText(
      [
        "2026-08-26_10:01:00 [INFO] 电量80 停止充电 [/sys/x]",
        "2026-08-26_10:01:03 [WARN] drift",
        "2026-08-26_10:05:00 [INFO] 电量75 恢复充电 [/sys/x]",
      ].join("\n"),
    );
    const sessions = filterLogSessions(groupLogSessions(entries), LogLevel.Info);
    expect(sessions).toHaveLength(1);
    expect(
      sessions[0]!.entries.every((e) => e.level === LogLevel.Info || e.context),
    ).toBe(true);
  });
});
