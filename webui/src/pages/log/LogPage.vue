<script setup lang="ts">
import { ThemePack } from "@/shared";
import { useLogPage } from "./composables/useLogPage";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const LogMd3 = lazyComponent(() => import("./ui/LogMd3.vue"));
const LogMiuix = lazyComponent(() => import("./ui/LogMiuix.vue"));
const LogDefault = lazyComponent(() => import("./ui/LogDefault.vue"));

const {
  theme,
  packClass,
  levelFilter,
  viewMode,
  visibleLogLines,
  logSessions,
  filterActive,
  onButtonRefresh,
  onClear,
} = useLogPage();
</script>

<template>
  <div class="page" :class="packClass">
    <LogMd3
      v-if="theme.themePack === ThemePack.Md3"
      :lines="visibleLogLines"
      :sessions="logSessions"
      :view-mode="viewMode"
      :level-filter="levelFilter"
      :filter-active="filterActive"
      @update:level-filter="levelFilter = $event"
      @update:view-mode="viewMode = $event"
      @refresh="onButtonRefresh"
      @clear="onClear"
    />
    <LogMiuix
      v-else-if="theme.themePack === ThemePack.Miuix"
      :lines="visibleLogLines"
      :sessions="logSessions"
      :view-mode="viewMode"
      :level-filter="levelFilter"
      :filter-active="filterActive"
      @update:level-filter="levelFilter = $event"
      @update:view-mode="viewMode = $event"
      @refresh="onButtonRefresh"
      @clear="onClear"
    />
    <LogDefault
      v-else
      :lines="visibleLogLines"
      :sessions="logSessions"
      :view-mode="viewMode"
      :level-filter="levelFilter"
      :filter-active="filterActive"
      @update:level-filter="levelFilter = $event"
      @update:view-mode="viewMode = $event"
      @refresh="onButtonRefresh"
      @clear="onClear"
    />
  </div>
</template>

<style scoped lang="scss">
.page {
  min-height: calc(100dvh - 56px - var(--qsc-inset-top, 0px) - var(--dock-pad, 72px));
}
</style>
