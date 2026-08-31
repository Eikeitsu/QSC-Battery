import { computed, nextTick, onMounted, provide, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useThemePackClass } from "@/composables";
import { useAppStore } from "@/stores";
import { isTabName, TabName } from "@/shared";
import { preloadTab } from "@/router/loaders";

export function useAppShell() {
  const store = useAppStore();
  const { theme, packClass: shellClass } = useThemePackClass("shell");
  const route = useRoute();
  const router = useRouter();
  const refreshing = ref(false);
  const routeLoading = ref(false);
  const pendingTab = ref<TabName | null>(null);
  let navigationId = 0;
  const NAVIGATION_TIMEOUT_MS = 8_000;
  const scrollPositions = new Map<TabName, number>();

  const tab = computed<TabName>(
    () => pendingTab.value ?? (isTabName(route.name) ? route.name : TabName.Home),
  );

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
    const requestId = ++navigationId;
    saveScrollPosition();
    pendingTab.value = next;
    routeLoading.value = true;
    store.setInteractiveTab(next === TabName.Home);
    // 预取只是 best-effort；它和 router.replace 共享 import 缓存，不能阻塞点击。
    void preloadTab(next).catch(() => undefined);
    void navigateTo(next, requestId);
  }

  async function navigateTo(target: TabName, requestId: number) {
    try {
      // 路由切换必须在点击处理的同一轮开始，动态 chunk 由 RouterView 自己懒加载。
      await withTimeout(router.replace({ name: target }), NAVIGATION_TIMEOUT_MS);
      await nextTick();
      if (requestId !== navigationId || pendingTab.value !== target) return;
      restoreScrollPosition(target);
      pendingTab.value = null;
      routeLoading.value = false;
      requestAnimationFrame(() => theme.syncStatusBar());
    } catch {
      // 旧导航被快速点击取消时，不得清掉新导航的 loading 或选中态。
      if (requestId === navigationId && pendingTab.value === target) {
        pendingTab.value = null;
        routeLoading.value = false;
        store.setInteractiveTab(route.name === TabName.Home);
      }
    }
  }

  provide("setTab", setTab);

  function saveScrollPosition() {
    const current = route.name;
    const main = document.querySelector<HTMLElement>(".app-main");
    if (isTabName(current) && main) {
      scrollPositions.set(current, main.scrollTop);
    }
  }

  function restoreScrollPosition(target: TabName) {
    const top = scrollPositions.get(target) ?? 0;
    requestAnimationFrame(() => {
      if (router.currentRoute.value.name === target) {
        document.querySelector<HTMLElement>(".app-main")?.scrollTo(0, top);
      }
    });
  }

  async function onRefreshHome() {
    refreshing.value = true;
    try {
      await store.refreshStatus(true);
    } finally {
      refreshing.value = false;
    }
  }

  onMounted(async () => {
    theme.load();
    theme.bindSystemListener();
    await store.init();
    store.setInteractiveTab(route.name === TabName.Home);
    theme.syncStatusBar();
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
