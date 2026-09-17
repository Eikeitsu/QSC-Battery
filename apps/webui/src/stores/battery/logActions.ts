import { showSuccessToast, showToast } from "vant";
import { PATHS } from "@/shared";
import * as api from "@/shared/api";
import type { Ref } from "vue";

export function createLogActions(
  logText: Ref<string>,
  logLines: Ref<number>,
  logSize: Ref<string>,
) {
  async function refreshLog(showTip = false): Promise<void> {
    const [logR, sizeR] = await Promise.all([
      api.exec(`tail -n 80 '${PATHS.LOG_FILE}' 2>/dev/null`),
      api.exec(`wc -c < '${PATHS.LOG_FILE}' 2>/dev/null`),
    ]);
    const text = logR.stdout.trim();
    logText.value = text || "暂无日志（触发功能后才会写入）";
    logLines.value = text ? text.split("\n").filter(Boolean).length : 0;
    const sizeRaw = parseInt(sizeR.stdout.trim(), 10);
    if (Number.isNaN(sizeRaw)) logSize.value = "--";
    else if (sizeRaw < 1024) logSize.value = `${sizeRaw} B`;
    else if (sizeRaw < 1024 * 1024) logSize.value = `${(sizeRaw / 1024).toFixed(1)} KB`;
    else logSize.value = `${(sizeRaw / 1024 / 1024).toFixed(2)} MB`;
    if (!showTip) return;
    if (logR.errno === -2) showToast("日志读取超时");
    else showSuccessToast("日志已刷新");
  }

  async function clearLog(): Promise<void> {
    await api.exec(`: > '${PATHS.LOG_FILE}'`);
    await refreshLog(false);
    showSuccessToast("日志已清空");
  }

  return { refreshLog, clearLog };
}
