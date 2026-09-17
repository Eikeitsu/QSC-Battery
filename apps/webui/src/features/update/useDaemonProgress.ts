import { ref, type Ref } from "vue";
import * as api from "@/shared/api";

export function useDaemonProgress(actionBusy: Ref<"" | "module" | "app" | "daemon">) {
  const progress = ref<api.DaemonDownloadProgress>({ percent: 0, stage: "" });
  let progressTimer: ReturnType<typeof setInterval> | null = null;

  function startProgress(seed: api.DaemonDownloadProgress) {
    if (progressTimer) clearInterval(progressTimer);
    progress.value = seed;
    progressTimer = setInterval(() => {
      void api.loadDaemonDownloadProgress().then((p) => {
        if (!actionBusy.value) return;
        // 忽略上次失败残留，避免一闪「失败」
        if (p.stage === "failed") return;
        if (!p.stage && p.percent <= 0) return;
        // 进度只前进，避免抖动回退
        const nextPct = Math.max(progress.value.percent, p.percent);
        progress.value = { percent: nextPct, stage: p.stage || progress.value.stage };
      });
    }, 400);
  }

  function stopProgress() {
    if (progressTimer) clearInterval(progressTimer);
    progressTimer = null;
    progress.value = { percent: 0, stage: "" };
  }

  return { progress, startProgress, stopProgress };
}
