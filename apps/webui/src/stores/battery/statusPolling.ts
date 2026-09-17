import { STATUS_INTERVAL } from "@/shared";
import type { Ref } from "vue";

export type StatusPollingOpts = {
  ready: Ref<boolean>;
  refreshStatus: (showTip?: boolean) => Promise<void>;
};

export function createStatusPolling(opts: StatusPollingOpts) {
  const { ready, refreshStatus } = opts;

  let statusTimer: ReturnType<typeof setInterval> | null = null;
  let interactivePage = true;
  let pageVisible = true;
  let visibilityBound = false;

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
      if (changed) void refreshStatus();
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
