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

    <main class="app-main" :aria-busy="store.initializing">
      <PageLoading v-if="store.initializing" text="正在读取设备信息…" />
      <div class="route-content" :class="{ 'route-content--hidden': routeLoading }">
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
            <PageLoading text="正在打开页面…" />
          </template>
        </Suspense>
      </div>
    </main>

    <div v-if="routeLoading" class="route-loading-page" role="status" aria-live="polite">
      <div class="route-loader">
        <span class="route-loader__spinner" aria-hidden="true"></span>
        <span class="route-loader__text">正在切换页面</span>
        <span class="route-loader__dots" aria-hidden="true">···</span>
      </div>
    </div>

    <AppDock :tab="tab" @update:tab="setTab" />
  </div>
</template>

<style scoped lang="scss">
.shell-default .app-main {
  --qsc-topbar-h: 56px;

  padding-top: calc(56px + var(--qsc-inset-top, 0px));
}

.shell-md3 .app-main {
  --qsc-topbar-h: 72px;

  padding-top: calc(72px + var(--qsc-inset-top, 0px));
}

.shell-miuix .app-main {
  --qsc-topbar-h: 48px;

  padding-top: calc(48px + var(--qsc-inset-top, 0px));
}

.route-content {
  min-height: calc(
    100dvh - var(--qsc-topbar-h, 56px) - var(--qsc-inset-top, 0px) - var(--dock-pad, 72px)
  );
}

.route-content--hidden {
  display: none;
  pointer-events: none;
}

.route-loading-page {
  position: fixed;
  z-index: 30;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 24px;
  background: color-mix(in srgb, var(--qsc-bg) 92%, transparent);
  pointer-events: none;
}

.route-loader {
  display: grid;
  justify-items: center;
  gap: 10px;
  min-width: 156px;
  padding: 20px 24px;
  background: var(--qsc-surface);
  border: 1px solid color-mix(in srgb, var(--qsc-primary) 16%, transparent);
  border-radius: 18px;
  box-shadow: var(--qsc-shadow);
}

.route-loader__spinner {
  width: 26px;
  height: 26px;
  border: 3px solid color-mix(in srgb, var(--qsc-primary) 18%, transparent);
  border-top-color: var(--qsc-primary);
  border-radius: 50%;
  animation: route-loader-spin 0.75s linear infinite;
}

.route-loader__text {
  color: var(--qsc-text);
  font-size: 14px;
  font-weight: 600;
}

.route-loader__dots {
  color: var(--qsc-text-2);
  font-size: 18px;
  line-height: 10px;
  letter-spacing: 3px;
  animation: route-loader-dots 1s ease-in-out infinite;
}

.shell-md3 .route-loader {
  min-width: 188px;
  border-radius: 28px;
  box-shadow: none;
}

.shell-md3 .route-loader__spinner {
  width: 140px;
  height: 5px;
  overflow: hidden;
  border: 0;
  border-radius: 999px;
  background: color-mix(in srgb, var(--qsc-primary) 18%, transparent);
  animation: none;
}

.shell-md3 .route-loader__spinner::after {
  display: block;
  width: 42%;
  height: 100%;
  border-radius: inherit;
  background: var(--qsc-primary);
  content: "";
  animation: route-loader-progress 1.1s ease-in-out infinite;
}

.shell-miuix .route-loader {
  min-width: 148px;
  border: 0;
  border-radius: 24px;
  background: color-mix(in srgb, var(--qsc-surface) 86%, transparent);
  box-shadow: 0 12px 36px color-mix(in srgb, var(--qsc-primary) 16%, transparent);
}

.shell-miuix .route-loader__spinner {
  width: 12px;
  height: 12px;
  border-width: 2px;
}

@keyframes route-loader-spin {
  to {
    transform: rotate(360deg);
  }
}

@keyframes route-loader-dots {
  0%,
  100% {
    opacity: 0.35;
  }

  50% {
    opacity: 1;
  }
}

@keyframes route-loader-progress {
  0% {
    transform: translateX(-120%);
  }

  100% {
    transform: translateX(340%);
  }
}
</style>
