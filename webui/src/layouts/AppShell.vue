<script setup lang="ts">
import { slideDir } from "@/router";
import { useAppShell } from "./composables/useAppShell";
import AppTopbar from "./ui/AppTopbar.vue";
import AppDock from "./ui/AppDock.vue";

const { shellClass, theme, tab, refreshing, setTab, onRefreshHome } = useAppShell();
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
      <RouterView v-slot="{ Component, route: viewRoute }">
        <Transition
          :name="slideDir === 'forward' ? 'slide-left' : 'slide-right'"
          mode="out-in"
        >
          <component
            :is="Component"
            :key="viewRoute.name"
            :refreshing="viewRoute.name === 'home' ? refreshing : undefined"
            @refresh="onRefreshHome()"
          />
        </Transition>
      </RouterView>
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
