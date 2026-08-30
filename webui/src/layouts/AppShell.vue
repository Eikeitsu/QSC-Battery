<script setup lang="ts">
import { RouterView } from "vue-router";
import { useAppShell } from "./composables/useAppShell";
import AppTopbar from "./ui/AppTopbar.vue";
import AppDock from "./ui/AppDock.vue";
import PageLoading from "@/shared/ui/PageLoading.vue";
import { useAppStore } from "@/stores";

const { shellClass, theme, tab, refreshing, routeLoading, setTab, onRefreshHome } =
  useAppShell();
const store = useAppStore();
</script>

<template>
  <div
    class="app-shell"
    :class="shellClass"
    :data-theme="theme.resolved"
    :data-pack="theme.themePack"
  >
    <AppTopbar />

    <main
      class="app-main"
      :aria-busy="store.initializing || store.hydrating || routeLoading"
    >
      <div
        v-if="store.initializing || store.hydrating || routeLoading"
        class="app-main-loading"
        role="status"
      >
        <span class="app-main-loading__bar" aria-hidden="true"></span>
        <span>{{
          routeLoading
            ? "正在打开页面…"
            : store.hydrating
              ? "正在同步页面数据…"
              : "正在读取设备信息…"
        }}</span>
      </div>
      <div class="route-content">
        <Suspense timeout="0">
          <template #default>
            <RouterView v-slot="{ Component, route: viewRoute }">
              <KeepAlive :max="4">
                <component
                  :is="Component"
                  :key="viewRoute.name"
                  :refreshing="viewRoute.name === 'home' ? refreshing : undefined"
                  @refresh="onRefreshHome()"
                />
              </KeepAlive>
            </RouterView>
          </template>
          <template #fallback>
            <PageLoading text="正在准备页面…" />
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

.app-main-loading {
  position: fixed;
  top: calc(var(--qsc-topbar-h, 56px) + var(--qsc-inset-top, 0));
  left: 0;
  right: 0;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 8px;
  height: 28px;
  padding: 0 16px;
  background: color-mix(in srgb, var(--qsc-bg) 92%, transparent);
  color: var(--qsc-text);
  font-size: 12px;
  pointer-events: none;
}

.app-main-loading__bar {
  width: 36px;
  height: 3px;
  overflow: hidden;
  border-radius: 999px;
  background: color-mix(in srgb, var(--qsc-primary) 20%, transparent);
}

.app-main-loading__bar::after {
  display: block;
  width: 45%;
  height: 100%;
  background: var(--qsc-primary);
  content: "";
  animation: app-main-loading-progress 1s ease-in-out infinite;
}

@keyframes app-main-loading-progress {
  from {
    transform: translateX(-120%);
  }

  to {
    transform: translateX(240%);
  }
}
</style>
