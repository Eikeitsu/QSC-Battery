<script setup lang="ts">
import { computed, onMounted, provide, ref, type Component } from "vue";
import Home from "./pages/Home.vue";
import Config from "./pages/Config.vue";
import Log from "./pages/Log.vue";
import More from "./pages/More.vue";
import { useAppStore, useTheme } from "./stores";
import type { TabName } from "./shared/types";

const store = useAppStore();
const theme = useTheme();

const savedTab = localStorage.getItem("qsc_dock_page");
const tab = ref<TabName>(
  savedTab === "home" ||
    savedTab === "config" ||
    savedTab === "log" ||
    savedTab === "more"
    ? savedTab
    : "home",
);
const refreshing = ref(false);
const slideDir = ref<"forward" | "back">("forward");
const order: TabName[] = ["home", "config", "log", "more"];

const views: Record<TabName, Component> = {
  home: Home,
  config: Config,
  log: Log,
  more: More,
};

const activeView = computed(() => views[tab.value] || Home);

function setTab(name: string | number) {
  const next = String(name) as TabName;
  if (!order.includes(next)) return;
  const from = order.indexOf(tab.value);
  const to = order.indexOf(next);
  slideDir.value = to >= from ? "forward" : "back";
  tab.value = next;
  try {
    localStorage.setItem("qsc_dock_page", next);
  } catch {
    /* ignore */
  }
}

provide("setTab", setTab);

async function onRefreshHome() {
  refreshing.value = true;
  try {
    await store.refreshStatus(true);
  } finally {
    refreshing.value = false;
  }
}

async function onRefreshLog() {
  refreshing.value = true;
  try {
    await store.refreshLog(true);
  } finally {
    refreshing.value = false;
  }
}

onMounted(async () => {
  theme.load();
  theme.bindSystemListener();
  await store.init();
});
</script>

<template>
  <div class="app-shell" :data-theme="theme.resolved">
    <header class="topbar">
      <img class="logo" src="/img/icon.png" width="36" height="36" alt="" />
      <div class="titles">
        <h1>充电控制</h1>
        <p>{{ store.deviceName }}</p>
      </div>
    </header>

    <main class="main">
      <Transition
        :name="slideDir === 'forward' ? 'slide-left' : 'slide-right'"
        mode="out-in"
      >
        <component
          :is="activeView"
          :key="tab"
          :refreshing="refreshing"
          @refresh="tab === 'log' ? onRefreshLog() : onRefreshHome()"
        />
      </Transition>
    </main>

    <van-tabbar
      :model-value="tab"
      safe-area-inset-bottom
      active-color="var(--qsc-primary)"
      inactive-color="var(--qsc-text-3)"
      @update:model-value="setTab"
    >
      <van-tabbar-item name="home" icon="home-o">概览</van-tabbar-item>
      <van-tabbar-item name="config" icon="setting-o">策略</van-tabbar-item>
      <van-tabbar-item name="log" icon="notes-o">日志</van-tabbar-item>
      <van-tabbar-item name="more" icon="user-o">我的</van-tabbar-item>
    </van-tabbar>
  </div>
</template>

<style scoped lang="scss">
.app-shell {
  min-height: 100vh;
  min-height: 100dvh;
  background: var(--qsc-bg);
  color: var(--qsc-text);
  padding-bottom: calc(52px + env(safe-area-inset-bottom));
}

.topbar {
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: calc(12px + env(safe-area-inset-top)) 16px 12px;
  background: color-mix(in srgb, var(--qsc-surface) 86%, transparent);
  -webkit-backdrop-filter: blur(18px);
  backdrop-filter: blur(18px);
  border-bottom: 1px solid var(--qsc-hairline);
}

.logo {
  border-radius: 10px;
}

.titles h1 {
  margin: 0;
  font-size: 17px;
  font-weight: 760;
  line-height: 1.2;
  letter-spacing: -0.02em;
}

.titles p {
  margin: 3px 0 0;
  font-size: 12px;
  color: var(--qsc-text-3);
  max-width: 70vw;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.main {
  position: relative;
  overflow-x: hidden;
}
</style>
