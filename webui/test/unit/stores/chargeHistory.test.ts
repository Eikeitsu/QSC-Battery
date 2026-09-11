import { beforeEach, describe, expect, it, vi } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { mergeHistory } from "@/shared/api/history";
import type { HistoryPoint } from "@/shared/api/history";
import {
  FAST_TTL_MS,
  SYSTEM_TTL_MS,
  applyPoints,
  needsSystemHistory,
  useChargeHistoryStore,
} from "@/stores/chargeHistory";

vi.mock("@/shared/api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/shared/api")>();
  return {
    ...actual,
    loadChargeHistory: vi.fn(),
    loadSystemBatteryHistory: vi.fn(),
  };
});

import * as api from "@/shared/api";

const point = (
  ts: number,
  level: number,
  currentUa: number | null = null,
): HistoryPoint => ({
  ts,
  level,
  temp: 30,
  currentUa,
  status: "",
  source: "",
});

describe("chargeHistory helpers", () => {
  it("needs system history when sampling is off", () => {
    expect(needsSystemHistory(false, [point(1, 50)])).toBe(true);
  });

  it("needs system history when sampled points are insufficient", () => {
    expect(needsSystemHistory(true, [point(1, 50)])).toBe(true);
    expect(needsSystemHistory(true, [point(1, 50), point(2, 49)])).toBe(false);
  });

  it("applyPoints prefers merged, sampled, then system", () => {
    const sampled = [point(100, 80, 1_000_000)];
    const system = [point(200, 79)];
    expect(applyPoints(sampled, system).source).toBe("merged");
    expect(applyPoints(sampled, []).source).toBe("sampled");
    expect(applyPoints([], system).source).toBe("system");
    expect(applyPoints([], []).points).toEqual([]);
  });

  it("applyPoints uses mergeHistory for merged source", () => {
    const sampled = [point(600, 80, 1_000_000)];
    const system = [point(610, 80), point(1200, 79)];
    const merged = applyPoints(sampled, system);
    expect(merged.points.map((p) => p.ts)).toEqual(
      mergeHistory(sampled, system).map((p) => p.ts),
    );
  });
});

describe("useChargeHistoryStore", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    setActivePinia(createPinia());
    vi.mocked(api.loadChargeHistory).mockReset();
    vi.mocked(api.loadSystemBatteryHistory).mockReset();
  });

  it("loads CSV first and skips dumpsys when sampled data is enough", async () => {
    vi.mocked(api.loadChargeHistory).mockResolvedValue([
      point(1, 90, 500_000),
      point(2, 89, 500_000),
    ]);
    vi.mocked(api.loadSystemBatteryHistory).mockResolvedValue([point(3, 88)]);

    const store = useChargeHistoryStore();
    store.activate(true);
    await vi.runOnlyPendingTimersAsync();

    expect(store.points).toHaveLength(2);
    expect(store.source).toBe("sampled");
    expect(api.loadChargeHistory).toHaveBeenCalledTimes(1);
    expect(api.loadSystemBatteryHistory).not.toHaveBeenCalled();
  });

  it("defers system history when sampling is disabled", async () => {
    vi.mocked(api.loadSystemBatteryHistory).mockResolvedValue([
      point(10, 70),
      point(20, 69),
    ]);

    const store = useChargeHistoryStore();
    store.activate(false);
    await vi.advanceTimersByTimeAsync(300);
    await Promise.resolve();

    expect(store.source).toBe("system");
    expect(api.loadSystemBatteryHistory).toHaveBeenCalledTimes(1);
  });

  it("respects fast TTL on tab re-activation", async () => {
    vi.mocked(api.loadChargeHistory).mockResolvedValue([point(1, 90), point(2, 89)]);

    const store = useChargeHistoryStore();
    store.activate(true);
    await vi.runOnlyPendingTimersAsync();

    store.deactivate();
    vi.mocked(api.loadChargeHistory).mockClear();

    store.onTabActivated(true);
    await Promise.resolve();

    expect(api.loadChargeHistory).not.toHaveBeenCalled();
    expect(store.points).toHaveLength(2);
  });

  it("aborts in-flight updates after deactivate", async () => {
    let resolveSystem!: (value: HistoryPoint[]) => void;
    vi.mocked(api.loadChargeHistory).mockResolvedValue([]);
    vi.mocked(api.loadSystemBatteryHistory).mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveSystem = resolve;
        }),
    );

    const store = useChargeHistoryStore();
    store.activate(false);
    await vi.advanceTimersByTimeAsync(300);

    store.deactivate();
    resolveSystem([point(1, 50), point(2, 49)]);
    await Promise.resolve();

    expect(store.points).toEqual([]);
  });

  it("refreshAll forces both sources", async () => {
    vi.mocked(api.loadChargeHistory).mockResolvedValue([
      point(1, 90, 500_000),
      point(2, 89, 500_000),
    ]);
    vi.mocked(api.loadSystemBatteryHistory).mockResolvedValue([point(3, 88)]);

    const store = useChargeHistoryStore();
    store.activate(true);
    await vi.runOnlyPendingTimersAsync();

    await store.refreshAll(true);

    expect(store.source).toBe("merged");
    expect(api.loadSystemBatteryHistory).toHaveBeenCalledTimes(1);
  });

  it("uses configured TTL constants", () => {
    expect(FAST_TTL_MS).toBe(30_000);
    expect(SYSTEM_TTL_MS).toBe(5 * 60_000);
  });
});
