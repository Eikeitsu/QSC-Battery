<script setup lang="ts">
import { RouterView } from "vue-router";
import { slideDir } from "@/router/state";
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
      <div v-if="routeLoading" class="route-loading" role="status" aria-live="polite">
        <PageLoading text="正在打开页面…" />
      </div>
      <div
        v-if="store.initializing"
        class="data-loading"
        role="status"
        aria-live="polite"
      >
        <span class="data-loading__spinner" aria-hidden="true"></span>
        <span>页面已打开，正在后台读取设备数据…</span>
      </div>
      <Suspense timeout="0">
        <template #default>
          <RouterView v-slot="{ Component, route: viewRoute }">
            <Transition :name="slideDir === 'forward' ? 'slide-left' : 'slide-right'">
              <component
                :is="Component"
                :key="viewRoute.name"
                :refreshing="viewRoute.name === 'home' ? refreshing : undefined"
                @refresh="onRefreshHome()"
              />
            </Transition>
          </RouterView>
        </template>
        <template #fallback>
          <PageLoading text="正在打开页面…" />
        </template>
      </Suspense>
    </main>

    <AppDock :tab="tab" @update:tab="setTab" />
  </div>
</template>

<style scoped lang="scss">
.shell-default .app-main {
  padding-top: calc(56px + var(--qsc-inset-top, 0px));
}

.shell-md3 .app-main {
  padding-top: calc(72px + var(--qsc-inset-top, 0px));
}

.shell-miuix .app-main {
  padding-top: calc(48px + var(--qsc-inset-top, 0px));
}

.route-loading {
  position: fixed;
  z-index: 20;
  inset: 0;
  display: grid;
  place-items: center;
  background: color-mix(in srgb, var(--qsc-bg) 72%, transparent);
  pointer-events: none;
}

.route-loading :deep(.page-loading) {
  min-width: 150px;
  border-radius: 12px;
  background: var(--qsc-surface);
  box-shadow: var(--qsc-shadow);
}

.data-loading {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 0 12px 8px;
  padding: 8px 12px;
  border: 1px solid color-mix(in srgb, var(--qsc-primary) 18%, transparent);
  border-radius: 10px;
  color: var(--qsc-text-2);
  font-size: 12px;
}

.data-loading__spinner {
  width: 13px;
  height: 13px;
  flex: 0 0 auto;
  border: 2px solid color-mix(in srgb, var(--qsc-primary) 22%, transparent);
  border-top-color: var(--qsc-primary);
  border-radius: 50%;
  animation: data-loading-spin 0.8s linear infinite;
}

@keyframes data-loading-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
