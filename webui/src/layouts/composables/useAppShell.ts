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

  const tab = computed<TabName>(
    () => pendingTab.value ?? (isTabName(route.name) ? route.name : TabName.Home),
  );

  function waitForPaint(): Promise<void> {
    return new Promise((resolve) => {
      requestAnimationFrame(() => {
        resolve();
      });
    });
  }

  function setTab(name: string | number) {
    const next = String(name);
    if (!isTabName(next) || next === tab.value) return;
    // 先更新选中态和顶部 loading，再异步解析目标页面；不隐藏当前滚动内容。
    navigationId += 1;
    pendingTab.value = next;
    routeLoading.value = true;
    cancelWarmup();
    void drainNavigation();
  }

  async function drainNavigation() {
    if (navigationRunning) return;
    navigationRunning = true;
    try {
      while (pendingTab.value) {
        const target = pendingTab.value;
        const requestId = navigationId;
        // 只让出一帧给选中态和顶部 loading，避免连续两帧等待放大点击延迟。
        await nextTick();
        await waitForPaint();
        if (requestId !== navigationId || pendingTab.value !== target) continue;

        // 预取和 router.replace 共享同一个动态 import 缓存；用户点击后立即开始
        // 下载目标 chunk，已加载页面则几乎同步完成。
        void preloadTab(target).catch(() => {});
        try {
          await router.replace({ name: target });
          await nextTick();
        } catch {
          // 当前目标加载失败时回到当前有效路由，不能留下永久 loading。
          if (requestId === navigationId && pendingTab.value === target) {
            pendingTab.value = null;
            routeLoading.value = false;
          }
          continue;
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
    if (warmCancelled) return;
    warmTimer = window.setTimeout(() => {
      if (warmCancelled) return;
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

  function warmNextRouteChunk() {
    if (warmCancelled) return;
    const name = TAB_ORDER.find((candidate) => candidate !== tab.value);
    if (name) void preloadTab(name).catch(() => {});
  }

  function cancelWarmup() {
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
    // 让首屏和滚动先稳定，再只预取一个相邻页面；不连续解析全部 Tab。
    scheduleWarmup(warmNextRouteChunk, 2500);
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
