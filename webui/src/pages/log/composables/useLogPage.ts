import { computed, ref, watch } from "vue";
import { showConfirmDialog } from "vant";
import { useThemePackClass } from "@/composables";
import {
  STORAGE_KEYS,
  filterLogEntries,
  filterLogSessions,
  groupLogSessions,
  isLogLevel,
  LogLevel,
  parseLogText,
  readStorage,
  writeStorage,
} from "@/shared";
import { useAppStore } from "@/stores";
import { clearChargeEvents } from "@/shared/api/events";
import { useChargeEvents } from "./useChargeEvents";

export type LogPageTab = "runtime" | "events";

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

function readLogTab(): LogPageTab {
  return readStorage(STORAGE_KEYS.logPageTab) === "events" ? "events" : "runtime";
}

export function useLogPage() {
  const store = useAppStore();
  const { theme, packClass } = useThemePackClass();
  const levelFilter = ref(readLevelFilter());
  const viewMode = ref<"flat" | "session">(readViewMode());
  const logTab = ref<LogPageTab>(readLogTab());
  const { eventsNewestFirst, loadingEvents, eventSummary, refreshEvents } =
    useChargeEvents(80);

  const logEntries = computed(() => parseLogText(store.logText));
  // 平铺：按等级滤行。会话：先全量分组，再组内滤行（边界行始终保留）。
  const visibleLogLines = computed(() =>
    filterLogEntries(logEntries.value, levelFilter.value),
  );
  const logSessions = computed(() =>
    filterLogSessions(groupLogSessions(logEntries.value), levelFilter.value),
  );
  const filterActive = computed(
    () => Boolean(levelFilter.value) && logEntries.value.length > 0,
  );

  watch(levelFilter, (v) => writeStorage(STORAGE_KEYS.logLevelFilter, v));
  watch(viewMode, (v) => writeStorage(STORAGE_KEYS.logViewMode, v));
  watch(logTab, (v) => writeStorage(STORAGE_KEYS.logPageTab, v));

  async function doRefresh(showTip: boolean) {
    if (logTab.value === "events") {
      await refreshEvents();
      return;
    }
    await store.refreshLog(showTip);
  }

  async function onButtonRefresh() {
    await doRefresh(true);
  }

  async function onClear() {
    if (logTab.value === "events") {
      try {
        await showConfirmDialog({
          title: "清空事件",
          message: "确认清空充电事件记录？此操作不可恢复。",
        });
      } catch {
        return;
      }
      await clearChargeEvents();
      await refreshEvents();
      return;
    }
    try {
      await showConfirmDialog({
        title: "清空日志",
        message: "确认清空运行日志？",
      });
    } catch {
      return;
    }
    await store.clearLog();
    theme.restoreChromeInsets?.();
  }

  return {
    store,
    theme,
    packClass,
    levelFilter,
    viewMode,
    logTab,
    eventsNewestFirst,
    loadingEvents,
    eventSummary,
    visibleLogLines,
    logSessions,
    filterActive,
    onButtonRefresh,
    onClear,
    refreshEvents,
  };
}
