import type { ExecResult } from "@/shared/types";

const EXEC_TIMEOUT = 8000;

export type ExecPriority = "high" | "low";

interface QueuedExec {
  cmd: string;
  timeoutMs: number;
  priority: ExecPriority;
  resolve: (result: ExecResult) => void;
}

let pumpRunning = false;
let pumpScheduled = false;
const queue: QueuedExec[] = [];

export function hasBridge(): boolean {
  return typeof ksu !== "undefined" && typeof ksu?.exec === "function";
}

/** 供单元测试重置队列状态 */
export function resetExecQueueForTests(): void {
  queue.length = 0;
  pumpRunning = false;
  pumpScheduled = false;
}

/** 队列中是否还有待执行的 high 任务（含正在跑的那条由 pumpRunning 体现） */
export function hasPendingHighExec(): boolean {
  return queue.some((task) => task.priority === "high");
}

function runExecOnce(cmd: string, timeoutMs: number): Promise<ExecResult> {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (result: ExecResult) => {
      if (settled) return;
      settled = true;
      resolve(result);
    };

    const timer = setTimeout(() => {
      finish({ errno: -2, stdout: "", stderr: "timeout" });
    }, timeoutMs);

    if (!hasBridge() || !ksu) {
      clearTimeout(timer);
      finish({ errno: -1, stdout: "", stderr: "no_ksu_bridge" });
      return;
    }

    const cb = `cb_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
    const win = window as unknown as Window & Record<string, unknown>;
    win[cb] = (errno: number, stdout: string, stderr: string) => {
      clearTimeout(timer);
      delete win[cb];
      finish({
        errno: typeof errno === "number" ? errno : 0,
        stdout: stdout == null ? "" : String(stdout),
        stderr: stderr == null ? "" : String(stderr),
      });
    };

    try {
      ksu.exec(cmd, "{}", cb);
    } catch (error) {
      try {
        ksu.exec(cmd, cb as unknown as string);
      } catch (error2) {
        clearTimeout(timer);
        delete win[cb];
        finish({ errno: -1, stdout: "", stderr: String(error2 || error) });
      }
    }
  });
}

function pickNextTask(): QueuedExec | null {
  const highIdx = queue.findIndex((task) => task.priority === "high");
  if (highIdx >= 0) return queue.splice(highIdx, 1)[0] ?? null;
  if (queue.length > 0) return queue.shift() ?? null;
  return null;
}

async function pumpExecQueue(): Promise<void> {
  if (pumpRunning) return;
  pumpRunning = true;
  try {
    while (queue.length > 0) {
      const task = pickNextTask();
      if (!task) break;
      const result = await runExecOnce(task.cmd, task.timeoutMs);
      task.resolve(result);
    }
  } finally {
    pumpRunning = false;
    if (queue.length > 0) schedulePumpExec();
  }
}

function schedulePumpExec(): void {
  if (pumpScheduled || pumpRunning) return;
  pumpScheduled = true;
  queueMicrotask(() => {
    pumpScheduled = false;
    void pumpExecQueue();
  });
}

export function exec(
  cmd: string,
  timeoutMs = EXEC_TIMEOUT,
  priority: ExecPriority = "high",
): Promise<ExecResult> {
  return new Promise((resolve) => {
    queue.push({ cmd, timeoutMs, priority, resolve });
    schedulePumpExec();
  });
}

export function openUrl(url: string): Promise<ExecResult> {
  return exec(`am start -a android.intent.action.VIEW -d '${url}' >/dev/null 2>&1`);
}

export function openWxPay(url: string): Promise<ExecResult> {
  const safe = String(url || "").replace(/'/g, "");
  return exec(
    `am start -n com.tencent.mm/.plugin.webview.ui.tools.WebViewUI -d '${safe}' >/dev/null 2>&1`,
  );
}
