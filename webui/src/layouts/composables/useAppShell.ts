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
  let warmTimer: number | null = null;
  let warmIdle: number | null = null;
  let warmCancelled = false;

  const tab = computed<TabName>(
    () => pendingTab.value ?? (isTabName(route.name) ? route.name : TabName.Home),
  );

  async function setTab(name: string | number) {
    const next = String(name);
    if (!isTabName(next) || next === tab.value) return;
    // replace：Tab 不入历史栈，侧滑/虚拟返回可直接退出 WebUI
    const currentNavigationId = ++navigationId;
    pendingTab.value = next;
    routeLoading.value = true;
    scrollMainToTop();
    try {
      await router.replace({ name: next });
      await nextTick();
      if (currentNavigationId === navigationId) scrollMainToTop();
      requestAnimationFrame(() => theme.syncStatusBar());
    } catch {
      // 导航被取消时保留当前页面，不让加载状态卡住。
    } finally {
      if (currentNavigationId === navigationId) {
        pendingTab.value = null;
        routeLoading.value = false;
      }
    }
  }

  provide("setTab", setTab);

  function scrollMainToTop() {
    document.querySelector<HTMLElement>(".app-main")?.scrollTo(0, 0);
  }

  function scheduleWarmup(callback: () => void, delay: number) {
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

  function warmRouteChunks() {
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
    warmRouteChunks();
    theme.syncStatusBar();
    window.setTimeout(() => theme.syncStatusBar(), 200);
  });

  onUnmounted(() => {
    warmCancelled = true;
    if (warmTimer) clearTimeout(warmTimer);
    const idleWindow = window as Window & {
      cancelIdleCallback?: (handle: number) => void;
    };
    if (warmIdle !== null && idleWindow.cancelIdleCallback) {
      idleWindow.cancelIdleCallback(warmIdle);
    }
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
