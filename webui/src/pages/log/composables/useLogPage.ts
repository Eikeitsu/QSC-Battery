import { computed, ref, watch } from "vue";
import { showConfirmDialog } from "vant";
import { useThemePackClass } from "@/composables";
import {
  STORAGE_KEYS,
  filterLogEntries,
  groupLogSessions,
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

function readViewMode(): "flat" | "session" {
  return readStorage(STORAGE_KEYS.logViewMode) === "session" ? "session" : "flat";
}

export function useLogPage() {
  const store = useAppStore();
  const { theme, packClass } = useThemePackClass();
  const levelFilter = ref(readLevelFilter());
  const viewMode = ref<"flat" | "session">(readViewMode());

  const logEntries = computed(() => parseLogText(store.logText));
  const visibleLogLines = computed(() =>
    filterLogEntries(logEntries.value, levelFilter.value),
  );
  const logSessions = computed(() => groupLogSessions(visibleLogLines.value));
  const filterActive = computed(
    () => Boolean(levelFilter.value) && logEntries.value.length > 0,
  );

  watch(levelFilter, (v) => writeStorage(STORAGE_KEYS.logLevelFilter, v));
  watch(viewMode, (v) => writeStorage(STORAGE_KEYS.logViewMode, v));

  async function doRefresh(showTip: boolean) {
    await store.refreshLog(showTip);
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
    levelFilter,
    viewMode,
    visibleLogLines,
    logSessions,
    filterActive,
    onButtonRefresh,
    onClear,
  };
}
