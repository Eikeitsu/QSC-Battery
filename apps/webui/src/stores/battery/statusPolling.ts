import { STATUS_INTERVAL } from "@/shared";
import type { Ref } from "vue";

export type StatusPollingOpts = {
  ready: Ref<boolean>;
  refreshStatus: (showTip?: boolean) => Promise<void>;
  /** 最近一次状态刷新的 epoch ms；用于切回概览时跳过过勤的桥接读 */
  lastStatusAtMs?: Ref<number>;
};

export function createStatusPolling(opts: StatusPollingOpts) {
  const { ready, refreshStatus, lastStatusAtMs } = opts;

  let statusTimer: ReturnType<typeof setInterval> | null = null;
  let interactivePage = true;
  let pageVisible = true;
  let visibilityBound = false;
  // 切回概览时若刚刷过，勿立刻再 exec（WebView 桥接易卡 2–5s，#3）
  const TAB_REFRESH_MIN_GAP_MS = 4000;

  function pollingAllowed() {
    return ready.value && interactivePage && pageVisible;
  }

  function stopStatusPolling() {
    if (statusTimer) clearInterval(statusTimer);
    statusTimer = null;
  }

  function startStatusPolling() {
    if (statusTimer || !pollingAllowed()) return;
    statusTimer = setInterval(() => {
      void refreshStatus();
    }, STATUS_INTERVAL);
  }

  function setInteractiveTab(active: boolean) {
    const changed = interactivePage !== active;
    interactivePage = active;
    if (pollingAllowed()) {
      startStatusPolling();
      if (changed) {
        const last = lastStatusAtMs?.value ?? 0;
        const fresh = last > 0 && Date.now() - last < TAB_REFRESH_MIN_GAP_MS;
        if (!fresh) {
          // 让出一帧再刷，减轻切页卡顿感
          setTimeout(() => {
            if (pollingAllowed()) void refreshStatus();
          }, 120);
        }
      }
    } else {
      stopStatusPolling();
    }
  }

  function bindVisibilityListener() {
    if (visibilityBound || typeof document === "undefined") return;
    visibilityBound = true;
    pageVisible = !document.hidden;
    document.addEventListener("visibilitychange", () => {
      pageVisible = !document.hidden;
      if (pollingAllowed()) {
        startStatusPolling();
        void refreshStatus();
      } else {
        stopStatusPolling();
      }
    });
  }

  return {
    bindVisibilityListener,
    setInteractiveTab,
    startStatusPolling,
    stopStatusPolling,
  };
}
