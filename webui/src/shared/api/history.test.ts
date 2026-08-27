import { describe, expect, it } from "vitest";
import { mergeHistory, parseBatteryStatsHistory } from "./history";
import type { HistoryPoint } from "./history";

const SAMPLE = `
                    0 (9) RESET:TIME: 2026-08-27-10-00-00
                 +1m30s (2) 099 c0900422 status=discharging health=good plug=none temp=305 volt=4167
                 +5m00s (2) 098 c0900422 status=discharging plug=none temp=310 volt=4150
                 +1h2m3s456ms (2) 090 c0900422 status=charging plug=usb temp=330 volt=4200
                 not a history line
`;

describe("parseBatteryStatsHistory", () => {
  it("以 RESET:TIME 为基准还原时间与电量温度", () => {
    const points = parseBatteryStatsHistory(SAMPLE);
    expect(points).toHaveLength(3);

    const base = Math.floor(new Date(2026, 7, 27, 10, 0, 0).getTime() / 1000);
    expect(points[0].ts).toBe(base + 90);
    expect(points[0].level).toBe(99);
    expect(points[0].temp).toBe(31);
    expect(points[0].currentUa).toBeNull();
    expect(points[0].source).toBe("none");

    expect(points[2].ts).toBe(base + 3723);
    expect(points[2].source).toBe("usb");
    expect(points[2].status).toBe("charging");
  });

  it("无 RESET 行或空输入时返回空数组", () => {
    expect(parseBatteryStatsHistory("")).toEqual([]);
    expect(parseBatteryStatsHistory("+1m30s (2) 099 status=discharging")).toEqual([]);
  });
});

describe("mergeHistory", () => {
  const point = (ts: number, level: number, currentUa: number | null): HistoryPoint => ({
    ts,
    level,
    temp: 30,
    currentUa,
    status: "",
    source: "",
  });

  it("同分钟内保留模块采样点（含电流），其余用系统记录补齐", () => {
    const sampled = [point(600, 80, 1_000_000)];
    const system = [point(610, 80, null), point(1200, 79, null)];
    const merged = mergeHistory(sampled, system);
    expect(merged.map((p) => p.ts)).toEqual([600, 1200]);
    expect(merged[0].currentUa).toBe(1_000_000);
  });

  it("系统记录为空时原样返回", () => {
    const sampled = [point(1, 50, null)];
    expect(mergeHistory(sampled, [])).toBe(sampled);
  });
});
