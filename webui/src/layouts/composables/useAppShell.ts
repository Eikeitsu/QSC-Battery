import { computed, nextTick, onMounted, onUnmounted, provide, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useThemePackClass } from "@/composables";
import { useAppStore } from "@/stores";
import { isTabName, preloadTab } from "@/router/routes";
import { TabName } from "@/shared";
import { TAB_ORDER } from "@/shared/config/navigation";

export function useAppShell() {
  const store = useAppStore();
  const { theme, packClass: shellClass } = useThemePackClass("shell");
  const route = useRoute();
  const router = useRouter();
  const refreshing = ref(false);
  const routeLoading = ref(false);
  const pendingTab = ref<TabName | null>(null);
  let navigationId = 0;
  let navigationRunning = false;
  let warmTimer: number | null = null;
  let warmIdle: number | null = null;
  let warmCancelled = false;
  let warmPaused = false;

  const tab = computed<TabName>(
    () => pendingTab.value ?? (isTabName(route.name) ? route.name : TabName.Home),
  );

  function setTab(name: string | number) {
    const next = String(name);
    if (!isTabName(next) || next === tab.value) return;
    // replace：Tab 不入历史栈，侧滑/虚拟返回可直接退出 WebUI
    navigationId += 1;
    pendingTab.value = next;
    routeLoading.value = true;
    cancelWarmup();
    scrollMainToTop();
    void drainNavigation();
  }

  async function drainNavigation() {
    if (navigationRunning) return;
    navigationRunning = true;
    try {
      while (pendingTab.value) {
        const target = pendingTab.value;
        const requestId = navigationId;
        try {
          await router.replace({ name: target });
          await nextTick();
        } catch {
          // 失败时由下面的最新请求继续接管，避免 loading 永久卡住。
        }
        if (requestId !== navigationId || pendingTab.value !== target) continue;

        if (router.currentRoute.value.name === target) {
          scrollMainToTop();
          requestAnimationFrame(() => theme.syncStatusBar());
        }
        pendingTab.value = null;
        routeLoading.value = false;
      }
    } finally {
      navigationRunning = false;
      if (pendingTab.value) void drainNavigation();
    }
  }

  provide("setTab", setTab);

  function scrollMainToTop() {
    document.querySelector<HTMLElement>(".app-main")?.scrollTo(0, 0);
  }

  function scheduleWarmup(callback: () => void, delay: number) {
    if (warmCancelled || warmPaused) return;
    warmTimer = window.setTimeout(() => {
      if (warmCancelled || warmPaused) return;
      const idleWindow = window as Window & {
        requestIdleCallback?: (
          callback: () => void,
          options?: { timeout: number },
        ) => number;
      };
      if (idleWindow.requestIdleCallback) {
        warmIdle = idleWindow.requestIdleCallback(callback, { timeout: 1200 });
      } else {
        callback();
      }
    }, delay);
  }

  function warmRouteChunks() {
    if (warmCancelled || warmPaused) return;
    const queue = TAB_ORDER.filter((name) => name !== tab.value);
    const next = () => {
      if (warmCancelled) return;
      const name = queue.shift();
      if (!name) return;
      void preloadTab(name).finally(() => {
        scheduleWarmup(next, 250);
      });
    };
    scheduleWarmup(next, 500);
  }

  function cancelWarmup() {
    warmPaused = true;
    if (warmTimer) clearTimeout(warmTimer);
    warmTimer = null;
    const idleWindow = window as Window & {
      cancelIdleCallback?: (handle: number) => void;
    };
    if (warmIdle !== null && idleWindow.cancelIdleCallback) {
      idleWindow.cancelIdleCallback(warmIdle);
    }
    warmIdle = null;
  }

  async function onRefreshHome() {
    refreshing.value = true;
    try {
      await store.refreshStatus(true);
    } finally {
      refreshing.value = false;
      theme.restoreChromeInsets?.();
      theme.syncStatusBar();
    }
  }

  onMounted(async () => {
    theme.load();
    theme.bindSystemListener();
    const main = document.querySelector<HTMLElement>(".app-main");
    main?.addEventListener("scroll", cancelWarmup, { passive: true, once: true });
    await store.init();
    warmRouteChunks();
    theme.syncStatusBar();
    window.setTimeout(() => theme.syncStatusBar(), 200);
  });

  onUnmounted(() => {
    warmCancelled = true;
    cancelWarmup();
  });

  return {
    theme,
    shellClass,
    tab,
    refreshing,
    routeLoading,
    setTab,
    onRefreshHome,
  };
}
