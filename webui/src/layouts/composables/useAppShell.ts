import { computed, nextTick, onMounted, provide, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useThemePackClass } from "@/composables";
import { useAppStore } from "@/stores";
import { isTabName, preloadTab } from "@/router/routes";
import { TabName } from "@/shared";

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
  const NAVIGATION_TIMEOUT_MS = 8_000;

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

  function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
    return new Promise((resolve, reject) => {
      const timer = window.setTimeout(() => {
        reject(new Error("navigation_timeout"));
      }, timeoutMs);
      promise.then(
        (value) => {
          window.clearTimeout(timer);
          resolve(value);
        },
        (error: unknown) => {
          window.clearTimeout(timer);
          reject(error);
        },
      );
    });
  }

  function setTab(name: string | number) {
    const next = String(name);
    if (!isTabName(next) || next === tab.value) return;
    // 先更新选中态和顶部 loading，再异步解析目标页面；不隐藏当前滚动内容。
    navigationId += 1;
    pendingTab.value = next;
    routeLoading.value = true;
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
        try {
          // 先加载 chunk，再交给 router 切换；这样 chunk 超时时不会把
          // RouterView 留在半切换状态，后续点击仍可正常接管。
          await withTimeout(preloadTab(target), NAVIGATION_TIMEOUT_MS);
        } catch {
          if (requestId === navigationId && pendingTab.value === target) {
            pendingTab.value = null;
            routeLoading.value = false;
          }
          continue;
        }
        if (requestId !== navigationId || pendingTab.value !== target) continue;
        try {
          await withTimeout(router.replace({ name: target }), NAVIGATION_TIMEOUT_MS);
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
    await store.init();
    theme.syncStatusBar();
    window.setTimeout(() => theme.syncStatusBar(), 200);
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
