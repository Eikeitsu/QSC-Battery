import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { showConfirmDialog, showToast } from "vant";
import * as api from "@/shared/api";
import {
  STORAGE_KEYS,
  UPDATE_CHANNEL_HINT,
  UPDATE_CHANNEL_TECH,
  checkUpdateChannel,
  isPreferCdn,
  parseUpdateChannel,
  readStorage,
  setPreferCdn,
  writeStorage,
  type ChannelCheckResult,
  type UpdateChannel,
} from "@/shared";
import { actionBusyLabel } from "./actionLabels";
import { useDaemonProgress } from "./useDaemonProgress";

export function useUpdateChannelCard() {
  const channel = ref<UpdateChannel>(
    parseUpdateChannel(readStorage(STORAGE_KEYS.updateChannel)),
  );
  const preferCdn = ref(isPreferCdn());
  const busy = ref(false);
  const actionBusy = ref<"module" | "app" | "daemon" | "">("");
  const result = ref<ChannelCheckResult | null>(null);
  const showTech = ref(false);
  const bootstrapped = ref(false);
  const actionError = ref("");

  const { progress, startProgress, stopProgress } = useDaemonProgress(actionBusy);

  const hint = computed(() => UPDATE_CHANNEL_HINT[channel.value]);
  const tech = computed(() => UPDATE_CHANNEL_TECH[channel.value]);
  const daemonTitle = computed(() => {
    const impl = result.value?.daemonImpl === "c" ? "C" : "Rust";
    return `守护 · ${impl}`;
  });
  const actionBusyLabelText = computed(() =>
    actionBusyLabel(actionBusy.value, progress.value),
  );
  const progressPct = computed(() =>
    Math.max(0, Math.min(100, progress.value.percent || 0)),
  );

  async function selectChannel(next: UpdateChannel) {
    if (next === channel.value) return;
    if (next === "ci") {
      try {
        await showConfirmDialog({
          title: "切换到 CI？",
          message: "开发构建可能不稳定，仅建议排查问题或尝鲜时使用。确认切换？",
        });
      } catch {
        return;
      }
    }
    channel.value = next;
    writeStorage(STORAGE_KEYS.updateChannel, next);
  }

  function onPreferCdn(on: boolean) {
    preferCdn.value = on;
    setPreferCdn(on);
    void check(true);
  }

  async function check(silent = false) {
    busy.value = true;
    actionError.value = "";
    try {
      const r = await checkUpdateChannel(channel.value);
      result.value = r;
      if (r.error) showToast(r.error);
      else if (!silent) {
        if (!r.module && !r.app && !r.daemon) showToast("未获取到远端信息");
        else showToast("检查完成");
      }
    } catch (e) {
      showToast(e instanceof Error ? e.message : String(e));
    } finally {
      busy.value = false;
    }
  }

  async function updateModule() {
    const url = result.value?.module?.zipUrl;
    if (!url) {
      showToast("无模块下载地址");
      return;
    }
    if (result.value?.moduleCanSwitch) {
      try {
        await showConfirmDialog({
          title: "切回通道模块？",
          message: `本地模块高于当前通道，将无人值守刷入 ${result.value.module?.version || "通道版"}（跳过音量键）。失败则打开管理器。`,
        });
      } catch {
        return;
      }
    }
    actionBusy.value = "module";
    actionError.value = "";
    startProgress({ percent: 20, stage: "binary" });
    try {
      const r = await api.downloadAndOpenModuleInstaller(url);
      if (r.ok) {
        progress.value = { percent: 100, stage: "done" };
        if (r.mode === "cli") {
          showToast("模块已无人值守刷入，正在刷新界面…");
          await check(true);
          setTimeout(() => {
            const href = window.location.href.split("#")[0] || window.location.href;
            window.location.replace(
              `${href}${href.includes("?") ? "&" : "?"}_r=${Date.now()}`,
            );
          }, 800);
        } else {
          showToast("CLI 失败，已打开模块管理器，请确认刷写");
          await check(true);
        }
      } else {
        showToast(api.moduleInstallErrorText(r.error));
      }
    } catch (e) {
      showToast(e instanceof Error ? e.message : String(e));
    } finally {
      stopProgress();
      actionBusy.value = "";
    }
  }

  async function updateApp() {
    const url = result.value?.app?.apkUrl;
    if (!url) {
      showToast("无 APP 下载地址");
      return;
    }
    if (result.value?.appCanSwitch) {
      try {
        await showConfirmDialog({
          title: "切回通道 APP？",
          message: `本地 APP 高于当前通道。系统可能拒绝降级，失败请先卸载再装（${result.value.app?.version || "通道版"}）。`,
        });
      } catch {
        return;
      }
    }
    actionBusy.value = "app";
    actionError.value = "";
    startProgress({ percent: 25, stage: "binary" });
    try {
      const r = await api.downloadAndInstallApp(url);
      if (r.ok) {
        progress.value = { percent: 100, stage: "done" };
        showToast(r.mode === "pm" ? "APP 已安装" : "已打开系统安装界面，请完成安装");
        await check(true);
      } else {
        const msg = api.appInstallErrorText(r.error);
        actionError.value = msg;
        showToast(msg);
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      actionError.value = msg;
      showToast(msg);
    } finally {
      stopProgress();
      actionBusy.value = "";
    }
  }

  async function updateDaemon() {
    const d = result.value?.daemon;
    if (!d?.manifestUrl && !d?.baseUrl) {
      showToast("无守护清单");
      return;
    }
    if (result.value?.daemonCanSwitch) {
      try {
        await showConfirmDialog({
          title: "切回通道守护？",
          message: `本地守护高于当前通道，将热切换为 ${d.version || "通道版"}。`,
        });
      } catch {
        return;
      }
    }
    actionBusy.value = "daemon";
    actionError.value = "";
    await api.clearDaemonDownloadProgress().catch(() => undefined);
    startProgress({ percent: 5, stage: "prepare" });
    try {
      const st = await api.loadDaemonStatus().catch(() => null);
      const impl = st?.impl === "c" ? "c" : result.value?.daemonImpl === "c" ? "c" : "rust";
      const r = await api.installDaemon(impl, {
        manifestUrl: d.manifestUrl,
        pagesBase: d.baseUrl,
      });
      if (r.ok) {
        progress.value = { percent: 100, stage: "done" };
        showToast(r.version ? `守护已切换至 ${r.version}` : "守护已切换");
        await check(true);
      } else {
        const msg = api.daemonErrorText(r.error);
        actionError.value = msg;
        showToast(msg);
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      actionError.value = msg;
      showToast(msg);
    } finally {
      stopProgress();
      actionBusy.value = "";
    }
  }

  onMounted(async () => {
    await check(true);
    bootstrapped.value = true;
  });

  onUnmounted(stopProgress);

  watch(channel, async () => {
    if (!bootstrapped.value) return;
    await check(true);
  });

  return {
    channel,
    preferCdn,
    busy,
    actionBusy,
    result,
    showTech,
    actionError,
    hint,
    tech,
    daemonTitle,
    actionBusyLabelText,
    progressPct,
    selectChannel,
    onPreferCdn,
    check,
    updateModule,
    updateApp,
    updateDaemon,
  };
}
