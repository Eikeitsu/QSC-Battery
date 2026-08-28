<script setup lang="ts">
import { RouterView } from "vue-router";
import { slideDir } from "@/router/state";
import { useAppShell } from "./composables/useAppShell";
import AppTopbar from "./ui/AppTopbar.vue";
import AppDock from "./ui/AppDock.vue";
import PageLoading from "@/shared/ui/PageLoading.vue";
import { useAppStore } from "@/stores";

const { shellClass, theme, tab, refreshing, setTab, onRefreshHome } = useAppShell();
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

    <main class="app-main">
      <PageLoading v-if="store.initializing" text="正在读取设备数据…" />
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
</style>
