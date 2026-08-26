import { PATHS } from "@/shared/config/paths";
import { exec } from "./ksu";

export async function loadSwitchTestSummary(): Promise<string> {
  const result = await exec(
    `tail -n 40 '${PATHS.DATADIR}/switch_test.log' 2>/dev/null; echo '---'; cat '${PATHS.DATADIR}/switch_test_result' 2>/dev/null`,
  );
  return result.stdout.trim();
}

export async function runTestSwitch(
  full = false,
): Promise<{ ok: boolean; output: string }> {
  const max = full ? "" : "QSC_TEST_MAX=12 ";
  // 后台启动，避免 WebUI/管理器超时杀进程
  const result = await exec(`${max}sh '${PATHS.TEST_SWITCH_BG}' 2>&1`);
  return {
    ok: result.errno === 0,
    output: (result.stdout || result.stderr || "").trim(),
  };
}

export async function getSwitchTestStatus(): Promise<string> {
  const result = await exec(`cat '${PATHS.SWITCH_TEST_STATUS}' 2>/dev/null`);
  return result.stdout.trim();
}

export async function waitSwitchTestDone(
  timeoutMs = 180_000,
  pollMs = 2000,
): Promise<{ status: string; summary: string }> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const status = await getSwitchTestStatus();
    if (/^done|^error/.test(status)) {
      const summary = await loadSwitchTestSummary();
      return { status, summary };
    }
    await new Promise((r) => setTimeout(r, pollMs));
  }
  const status = await getSwitchTestStatus();
  const summary = await loadSwitchTestSummary();
  return { status: status || "timeout", summary };
}
