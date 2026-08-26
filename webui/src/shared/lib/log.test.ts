import { describe, expect, it } from "vitest";
import { LogLevel } from "@/shared/config/enums";
import { groupLogSessions, parseLogText } from "./log";

describe("parseLogText", () => {
  it("parses leveled lines", () => {
    const entries = parseLogText(
      "2026-08-26_10:00:00 [INFO] a\n2026-08-26_10:00:01 [WARN] b\n",
    );
    expect(entries).toHaveLength(2);
    expect(entries[0].level).toBe(LogLevel.Info);
    expect(entries[1].level).toBe(LogLevel.Warn);
  });

  it("treats empty hints as no entries", () => {
    expect(parseLogText("暂无日志")).toEqual([]);
  });
});

describe("groupLogSessions", () => {
  it("folds stop→resume and keeps latest open stop", () => {
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
    expect(sessions).toHaveLength(2);
    expect(sessions[0].open).toBe(true);
    expect(sessions[0].entries.some((e) => /停止充电/.test(e.raw))).toBe(true);
    expect(sessions[1].open).toBe(false);
    expect(sessions[1].entries).toHaveLength(4);
    expect(sessions[1].hasWarn).toBe(true);
  });
});
