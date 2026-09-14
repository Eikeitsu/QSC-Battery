import { computed, nextTick, onMounted, provide, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useThemePackClass } from "@/composables";
import { useAppStore } from "@/stores";
import { isTabName, parentTabOfRoute, TabName, type SubRouteName } from "@/shared";
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
  const scrollPositions = new Map<string, number>();

  const activeTab = computed<TabName>(() =>
    parentTabOfRoute(route.name, route.meta.parentTab),
  );

  const tab = computed<TabName>(() => pendingTab.value ?? activeTab.value);

  const isSubPage = computed(() => Boolean(route.meta.parentTab));
  const pageTitle = computed(() => {
    if (isSubPage.value && typeof route.meta.title === "string") {
      return route.meta.title;
    }
    return "";
  });

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
    if (!isTabName(next)) return;
    // 已在该 Tab 的 Hub 上则忽略；在子页上点同一底栏则回 Hub
    if (next === tab.value && !isSubPage.value && !pendingTab.value) return;
    const requestId = ++navigationId;
    saveScrollPosition();
    pendingTab.value = next;
    routeLoading.value = true;
    store.setInteractiveTab(next === TabName.Home);
    void preloadTab(next).catch(() => undefined);
    void navigateTo(next, requestId);
  }

  async function navigateTo(target: TabName, requestId: number) {
    try {
      await withTimeout(router.replace({ name: target }), NAVIGATION_TIMEOUT_MS);
      await nextTick();
      if (requestId !== navigationId || pendingTab.value !== target) return;
      restoreScrollPosition(target);
      pendingTab.value = null;
      routeLoading.value = false;
      requestAnimationFrame(() => theme.syncStatusBar());
    } catch {
      if (requestId === navigationId && pendingTab.value === target) {
        pendingTab.value = null;
        routeLoading.value = false;
        store.setInteractiveTab(activeTab.value === TabName.Home);
      }
    }
  }

  function openSub(name: SubRouteName) {
    saveScrollPosition();
    void router.push({ name }).then(() => {
      requestAnimationFrame(() => {
        document.querySelector<HTMLElement>(".app-main")?.scrollTo(0, 0);
        theme.syncStatusBar();
      });
    });
  }

  function goBack() {
    const parent = route.meta.parentTab;
    const hub = typeof parent === "string" && isTabName(parent) ? parent : TabName.Home;
    saveScrollPosition();
    void router.replace({ name: hub }).then(() => {
      restoreScrollPosition(hub);
      requestAnimationFrame(() => theme.syncStatusBar());
    });
  }

  provide("setTab", setTab);
  provide("openSub", openSub);

  function saveScrollPosition() {
    const key = String(route.name || "");
    const main = document.querySelector<HTMLElement>(".app-main");
    if (key && main) {
      scrollPositions.set(key, main.scrollTop);
    }
  }

  function restoreScrollPosition(target: string) {
    const top = scrollPositions.get(target) ?? 0;
    requestAnimationFrame(() => {
      if (String(router.currentRoute.value.name) === target) {
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
    store.setInteractiveTab(activeTab.value === TabName.Home);
    theme.syncStatusBar();
  });

  watch(activeTab, (t) => {
    store.setInteractiveTab(t === TabName.Home);
  });

  return {
    theme,
    shellClass,
    tab,
    isSubPage,
    pageTitle,
    refreshing,
    routeLoading,
    setTab,
    goBack,
    openSub,
    onRefreshHome,
  };
}
