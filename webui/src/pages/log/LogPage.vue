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
  logTab,
  visibleLogLines,
  logSessions,
  filterActive,
  eventsNewestFirst,
  loadingEvents,
  eventSummary,
  onButtonRefresh,
  onClear,
  refreshEvents,
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
      :log-tab="logTab"
      :events="eventsNewestFirst"
      :loading-events="loadingEvents"
      :event-summary="eventSummary"
      @update:level-filter="levelFilter = $event"
      @update:view-mode="viewMode = $event"
      @update:log-tab="logTab = $event"
      @refresh="onButtonRefresh"
      @clear="onClear"
      @refresh-events="refreshEvents"
    />
    <LogMiuix
      v-else-if="theme.themePack === ThemePack.Miuix"
      :lines="visibleLogLines"
      :sessions="logSessions"
      :view-mode="viewMode"
      :level-filter="levelFilter"
      :filter-active="filterActive"
      :log-tab="logTab"
      :events="eventsNewestFirst"
      :loading-events="loadingEvents"
      :event-summary="eventSummary"
      @update:level-filter="levelFilter = $event"
      @update:view-mode="viewMode = $event"
      @update:log-tab="logTab = $event"
      @refresh="onButtonRefresh"
      @clear="onClear"
      @refresh-events="refreshEvents"
    />
    <LogDefault
      v-else
      :lines="visibleLogLines"
      :sessions="logSessions"
      :view-mode="viewMode"
      :level-filter="levelFilter"
      :filter-active="filterActive"
      :log-tab="logTab"
      :events="eventsNewestFirst"
      :loading-events="loadingEvents"
      :event-summary="eventSummary"
      @update:level-filter="levelFilter = $event"
      @update:view-mode="viewMode = $event"
      @update:log-tab="logTab = $event"
      @refresh="onButtonRefresh"
      @clear="onClear"
      @refresh-events="refreshEvents"
    />
  </div>
</template>

<style scoped lang="scss">
.page {
  min-height: calc(100dvh - 56px - var(--qsc-inset-top, 0px) - var(--dock-pad, 72px));
}
</style>
