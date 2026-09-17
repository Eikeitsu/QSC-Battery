import type * as api from "@/shared/api";

export function actionBusyLabel(
  actionBusy: "" | "module" | "app" | "daemon",
  progress: api.DaemonDownloadProgress,
): string {
  if (actionBusy === "module") return "正在无人值守刷入模块…";
  if (actionBusy === "app") return "正在下载 APP…";
  if (actionBusy === "daemon") {
    const labels: Record<string, string> = {
      prepare: "正在准备…",
      manifest: "正在获取清单…",
      binary: "正在下载守护…",
      verify: "正在校验…",
      activate: "正在切换服务…",
      done: "已完成",
    };
    const stage = progress.stage;
    if (stage === "failed") return "正在更新守护…";
    return labels[stage] || "正在更新守护…";
  }
  return "";
}
