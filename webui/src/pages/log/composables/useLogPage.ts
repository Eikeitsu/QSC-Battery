import { ref } from "vue";
import { showConfirmDialog } from "vant";
import { useThemePackClass } from "@/composables";
import { useAppStore } from "@/stores";

export function useLogPage() {
  const store = useAppStore();
  const { theme, packClass } = useThemePackClass();
  const pullLoading = ref(false);

  async function doRefresh(showTip: boolean) {
    await store.refreshLog(showTip);
    theme.restoreChromeInsets?.();
    theme.syncStatusBar();
  }

  async function onPullRefresh() {
    pullLoading.value = true;
    try {
      await doRefresh(true);
    } finally {
      pullLoading.value = false;
      theme.restoreChromeInsets?.();
    }
  }

  async function onButtonRefresh() {
    await doRefresh(true);
  }

  async function onClear() {
    try {
      await showConfirmDialog({
        title: "清空日志",
        message: "确认清空运行日志？",
      });
      await store.clearLog();
      theme.restoreChromeInsets?.();
    } catch {
      /* cancelled */
    }
  }

  return {
    store,
    theme,
    packClass,
    pullLoading,
    onPullRefresh,
    onButtonRefresh,
    onClear,
  };
}
