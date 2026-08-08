import type { ExecResult } from "@/shared/types";

const EXEC_TIMEOUT = 8000;

export function hasBridge(): boolean {
  return typeof ksu !== "undefined" && typeof ksu?.exec === "function";
}

export function exec(cmd: string, timeoutMs = EXEC_TIMEOUT): Promise<ExecResult> {
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

export function openUrl(url: string): Promise<ExecResult> {
  return exec(`am start -a android.intent.action.VIEW -d '${url}' >/dev/null 2>&1`);
}

export function openWxPay(url: string): Promise<ExecResult> {
  const safe = String(url || "").replace(/'/g, "");
  return exec(
    `am start -n com.tencent.mm/.plugin.webview.ui.tools.WebViewUI -d '${safe}' >/dev/null 2>&1`,
  );
}
