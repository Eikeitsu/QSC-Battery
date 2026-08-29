import { computed, nextTick, onMounted, onUnmounted, provide, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useThemePackClass } from "@/composables";
import { useAppStore } from "@/stores";
import { isTabName, preloadTab } from "@/router/routes";
import { TabName } from "@/shared";
import { TAB_ORDER } from "@/shared/config/navigation";

// #region agent log
function debugUi(message: string, data: Record<string, unknown>, hypothesisId: string) {
  fetch("http://127.0.0.1:7292/ingest/058f1405-c7dd-4f7b-a005-ac16f2aae169", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Debug-Session-Id": "cb37f9" },
    body: JSON.stringify({
      sessionId: "cb37f9",
      runId: "ui-initial",
      hypothesisId,
      location: "useAppShell.ts",
      message,
      data,
      timestamp: Date.now(),
    }),
  }).catch(() => {});
}
// #endregion

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
    // #region agent log
    debugUi(
      "tab_request",
      { next, currentTab: tab.value, route: String(route.name) },
      "U1",
    );
    // #endregion
    if (!isTabName(next) || next === tab.value) return;
    // replace：Tab 不入历史栈，侧滑/虚拟返回可直接退出 WebUI
    navigationId += 1;
    pendingTab.value = next;
    // #region agent log
    debugUi("tab_pending", { next, navigationId }, "U1");
    // #endregion
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
        // 先让 Vue 把选中态和 loading 绘制出来，再启动首次懒加载。
        // 首次 chunk 的解析可能占用主线程；没有这一帧时，点击反馈会被推迟到路由完成。
        await nextTick();
        await new Promise<void>((resolve) => {
          requestAnimationFrame(() => resolve());
        });
        if (requestId !== navigationId || pendingTab.value !== target) continue;
        // 选中态先单独完成一次绘制，再显示遮罩；这样首次懒加载时用户能
        // 清楚看到点击已经生效，而不是等页面 chunk 加载完成后才变色。
        routeLoading.value = true;
        await nextTick();
        await new Promise<void>((resolve) => {
          requestAnimationFrame(() => resolve());
        });
        if (requestId !== navigationId || pendingTab.value !== target) {
          if (!pendingTab.value) routeLoading.value = false;
          continue;
        }
        try {
          await router.replace({ name: target });
          await nextTick();
          // #region agent log
          debugUi(
            "route_resolved",
            { target, route: String(router.currentRoute.value.name), requestId },
            "U2",
          );
          // #endregion
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
