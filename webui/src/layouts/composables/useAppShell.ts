import { computed, onMounted, provide, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useThemePackClass } from "@/composables";
import { useAppStore } from "@/stores";
import { isTabName } from "@/router/routes";
import { TabName } from "@/shared";

export function useAppShell() {
  const store = useAppStore();
  const { theme, packClass: shellClass } = useThemePackClass("shell");
  const route = useRoute();
  const router = useRouter();
  const refreshing = ref(false);

  const tab = computed<TabName>(() =>
    isTabName(route.name) ? route.name : TabName.Home,
  );

  function setTab(name: string | number) {
    const next = String(name);
    if (!isTabName(next) || next === tab.value) return;
    // replace：Tab 不入历史栈，侧滑/虚拟返回可直接退出 WebUI
    void router.replace({ name: next }).then(() => {
      requestAnimationFrame(() => theme.syncStatusBar());
    });
  }

  provide("setTab", setTab);

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
    setTab,
    onRefreshHome,
  };
}
