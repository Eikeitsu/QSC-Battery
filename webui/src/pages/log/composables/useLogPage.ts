import { computed, ref, watch } from "vue";
import { showConfirmDialog } from "vant";
import { useThemePackClass } from "@/composables";
import {
  STORAGE_KEYS,
  filterLogEntries,
  isLogLevel,
  LogLevel,
  parseLogText,
  readStorage,
  writeStorage,
} from "@/shared";
import { useAppStore } from "@/stores";

/** 空字符串 = 全部；未缓存时默认 Info */
function readLevelFilter(): string {
  const raw = readStorage(STORAGE_KEYS.logLevelFilter);
  if (raw === null) return LogLevel.Info;
  if (raw === "") return "";
  return isLogLevel(raw) ? raw : LogLevel.Info;
}

export function useLogPage() {
  const store = useAppStore();
  const { theme, packClass } = useThemePackClass();
  const pullLoading = ref(false);
  const levelFilter = ref(readLevelFilter());

  const logEntries = computed(() => parseLogText(store.logText));
  const visibleLogLines = computed(() =>
    filterLogEntries(logEntries.value, levelFilter.value),
  );
  const filterActive = computed(
    () => Boolean(levelFilter.value) && logEntries.value.length > 0,
  );

  watch(levelFilter, (v) => writeStorage(STORAGE_KEYS.logLevelFilter, v));

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
