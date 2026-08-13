import { computed, ref } from "vue";
import { showConfirmDialog } from "vant";
import { useThemePackClass } from "@/composables";
import { filterLogEntries, parseLogText } from "@/shared";
import { useAppStore } from "@/stores";

export function useLogPage() {
  const store = useAppStore();
  const { theme, packClass } = useThemePackClass();
  const pullLoading = ref(false);
  /** 空字符串 = 全部 */
  const levelFilter = ref("");

  const logEntries = computed(() => parseLogText(store.logText));
  const visibleLogLines = computed(() =>
    filterLogEntries(logEntries.value, levelFilter.value),
  );
  const filterActive = computed(() => Boolean(levelFilter.value));

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
    levelFilter,
    visibleLogLines,
    filterActive,
    onPullRefresh,
    onButtonRefresh,
    onClear,
  };
}
