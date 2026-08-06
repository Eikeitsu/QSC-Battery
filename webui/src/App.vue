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

const base = import.meta.env.BASE_URL;

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

const shellClass = computed(() => ({
  "shell-md3": theme.themePack === "md3",
  "shell-miuix": theme.themePack === "miuix",
  "shell-default": theme.themePack === "default",
}));

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
  requestAnimationFrame(() => theme.syncStatusBar());
}

provide("setTab", setTab);

async function onRefreshHome() {
  refreshing.value = true;
  try {
    await store.refreshStatus(true);
  } finally {
    refreshing.value = false;
    theme.syncStatusBar();
    requestAnimationFrame(() => theme.syncStatusBar());
  }
}

onMounted(async () => {
  theme.load();
  theme.bindSystemListener();
  await store.init();
  theme.syncStatusBar();
});
</script>

<template>
  <div
    class="app-shell"
    :class="shellClass"
    :data-theme="theme.resolved"
    :data-pack="theme.themePack"
  >
    <!-- MD3：大标题顶栏，无小图标主导 -->
    <header v-if="theme.themePack === 'md3'" class="app-topbar topbar-md3">
      <div class="md3-top">
        <p class="md3-eyebrow">{{ store.deviceName || "本机" }}</p>
        <h1>充电控制</h1>
      </div>
    </header>

    <!-- MIUIX：紧凑横排 -->
    <header v-else-if="theme.themePack === 'miuix'" class="app-topbar topbar-miuix">
      <div class="titles">
        <h1>充电控制</h1>
        <p>{{ store.deviceName }}</p>
      </div>
    </header>

    <!-- 默认 -->
    <header v-else class="app-topbar topbar-default">
      <img class="logo" :src="`${base}img/icon.png`" width="36" height="36" alt="" />
      <div class="titles">
        <h1>充电控制</h1>
        <p>{{ store.deviceName }}</p>
      </div>
    </header>

    <main class="app-main">
      <Transition
        :name="slideDir === 'forward' ? 'slide-left' : 'slide-right'"
        mode="out-in"
      >
        <component
          :is="activeView"
          :key="tab"
          :refreshing="refreshing"
          @refresh="onRefreshHome()"
        />
      </Transition>
    </main>

    <van-tabbar
      class="app-dock"
      :class="{
        'dock-md3': theme.themePack === 'md3',
        'dock-miuix': theme.themePack === 'miuix',
        'dock-default': theme.themePack === 'default',
      }"
      :model-value="tab"
      :safe-area-inset-bottom="false"
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
.logo {
  border-radius: 10px;
  flex-shrink: 0;
}

.titles {
  min-width: 0;
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

.topbar-md3 {
  flex-direction: column;
  align-items: stretch;
  justify-content: flex-end;
  min-height: calc(72px + var(--qsc-inset-top, 0px));
  padding-bottom: 12px;
}

.md3-top {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.md3-eyebrow {
  margin: 0;
  font-size: 12px;
  line-height: 1.35;
  color: var(--qsc-text-3);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.topbar-md3 h1 {
  margin: 0;
  font-size: 28px;
  font-weight: 650;
  letter-spacing: -0.4px;
  line-height: 1.2;
}

.topbar-miuix {
  min-height: calc(48px + var(--qsc-inset-top, 0px));
  padding-bottom: 6px;
}

.topbar-miuix .titles h1 {
  font-size: 18px;
  font-weight: 700;
}

.topbar-default .logo {
  border-radius: 12px;
  box-shadow: 0 1px 4px rgba(15, 18, 22, 0.1);
}

.topbar-default .titles h1 {
  font-size: 17px;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.shell-default .app-main {
  padding-top: calc(56px + var(--qsc-inset-top, 0px));
}

.shell-md3 .app-main {
  padding-top: calc(72px + var(--qsc-inset-top, 0px));
}

.shell-miuix .app-main {
  padding-top: calc(48px + var(--qsc-inset-top, 0px));
}
</style>
