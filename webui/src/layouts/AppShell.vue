<script setup lang="ts">
import { RouterView } from "vue-router";
import { useAppShell } from "./composables/useAppShell";
import AppTopbar from "./ui/AppTopbar.vue";
import AppDock from "./ui/AppDock.vue";
import { useAppStore } from "@/stores";

const {
  shellClass,
  theme,
  tab,
  isSubPage,
  pageTitle,
  refreshing,
  routeLoading,
  setTab,
  goBack,
  onRefreshHome,
} = useAppShell();
const store = useAppStore();
</script>

<template>
  <div
    class="app-shell"
    :class="shellClass"
    :data-theme="theme.resolved"
    :data-pack="theme.themePack"
  >
    <AppTopbar :sub-page="isSubPage" :page-title="pageTitle" @back="goBack" />

    <main class="app-main" :aria-busy="store.initializing || routeLoading">
      <div
        v-if="store.initializing || routeLoading"
        class="app-main-loading"
        role="status"
      >
        <span class="app-main-loading__bar" aria-hidden="true"></span>
        <span>{{ routeLoading ? "正在打开页面…" : "正在读取设备信息…" }}</span>
      </div>
      <div class="route-content">
        <Suspense timeout="0">
          <template #default>
            <RouterView v-slot="{ Component, route: viewRoute }">
              <KeepAlive :max="8">
                <component
                  :is="Component"
                  :key="String(viewRoute.name)"
                  :refreshing="viewRoute.name === 'home' ? refreshing : undefined"
                  @refresh="onRefreshHome()"
                />
              </KeepAlive>
            </RouterView>
          </template>
          <template #fallback>
            <div class="route-fallback" aria-hidden="true"></div>
          </template>
        </Suspense>
      </div>
    </main>

    <AppDock :tab="tab" @update:tab="setTab" />
  </div>
</template>

<style scoped lang="scss">
.shell-default .app-main {
  --qsc-topbar-h: 56px;

  padding-top: calc(56px + var(--qsc-inset-top, 0));
}

.shell-md3 .app-main {
  --qsc-topbar-h: 72px;

  padding-top: calc(72px + var(--qsc-inset-top, 0));
}

.shell-miuix .app-main {
  --qsc-topbar-h: 48px;

  padding-top: calc(48px + var(--qsc-inset-top, 0));
}

.route-content {
  min-height: calc(
    100dvh - var(--qsc-topbar-h, 56px) - var(--qsc-inset-top, 0) - var(--dock-pad, 72px)
  );
}

.route-fallback {
  min-height: 40vh;
}

.app-main-loading {
  position: sticky;
  top: calc(var(--qsc-topbar-h, 56px) + var(--qsc-inset-top, 0));
  z-index: 5;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 10px 16px 12px;
  font-size: 12px;
  color: var(--qsc-text-2);
  background: color-mix(in srgb, var(--qsc-bg) 92%, transparent);
  backdrop-filter: blur(8px);
}

.app-main-loading__bar {
  display: block;
  height: 3px;
  border-radius: 999px;
  overflow: hidden;
  background: color-mix(in srgb, var(--qsc-primary) 20%, transparent);
}

.app-main-loading__bar::after {
  content: "";
  display: block;
  width: 40%;
  height: 100%;
  border-radius: inherit;
  background: var(--qsc-primary);
  animation: qsc-load 1.1s ease-in-out infinite;
}

@keyframes qsc-load {
  0% {
    transform: translateX(-120%);
  }

  100% {
    transform: translateX(320%);
  }
}
</style>
