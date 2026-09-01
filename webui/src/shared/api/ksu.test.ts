import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { exec, resetExecQueueForTests } from "./ksu";

type KsuExec = (cmd: string, opts: string, cb: string) => void;

describe("exec priority queue", () => {
  const order: string[] = [];
  let delayMs = 0;

  beforeEach(() => {
    resetExecQueueForTests();
    order.length = 0;
    delayMs = 0;
    globalThis.window = globalThis as unknown as Window & typeof globalThis;

    (globalThis as typeof globalThis & { ksu: { exec: KsuExec } }).ksu = {
      exec(cmd: string, _opts: string, cb: string) {
        const win = globalThis as unknown as Record<
          string,
          (errno: number, stdout: string) => void
        >;
        const run = () => {
          order.push(cmd);
          win[cb]?.(0, cmd);
        };
        if (delayMs > 0) setTimeout(run, delayMs);
        else run();
      },
    };
  });

  afterEach(() => {
    delete (globalThis as typeof globalThis & { ksu?: { exec: KsuExec } }).ksu;
    resetExecQueueForTests();
    vi.useRealTimers();
  });

  it("runs high priority tasks before low priority tasks", async () => {
    const low = exec("low", 1000, "low");
    const high = exec("high", 1000, "high");
    await Promise.all([low, high]);
    expect(order).toEqual(["high", "low"]);
  });

  it("processes tasks serially through the bridge", async () => {
    delayMs = 5;
    vi.useFakeTimers();

    const first = exec("first", 1000, "high");
    const second = exec("second", 1000, "high");

    await vi.advanceTimersByTimeAsync(5);
    await first;
    await vi.advanceTimersByTimeAsync(5);
    await second;

    expect(order).toEqual(["first", "second"]);
  });

  it("resolves with timeout result when bridge is missing", async () => {
    delete (globalThis as typeof globalThis & { ksu?: { exec: KsuExec } }).ksu;
    const result = await exec("missing", 1000, "high");
    expect(result.errno).toBe(-1);
    expect(result.stderr).toBe("no_ksu_bridge");
  });
});
