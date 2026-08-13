<script setup lang="ts">
import { ThemePack } from "@/shared";
import { useLogPage } from "./composables/useLogPage";
import LogMd3 from "./ui/LogMd3.vue";
import LogMiuix from "./ui/LogMiuix.vue";
import LogDefault from "./ui/LogDefault.vue";

const {
  theme,
  packClass,
  pullLoading,
  levelFilter,
  visibleLogLines,
  filterActive,
  onPullRefresh,
  onButtonRefresh,
  onClear,
} = useLogPage();
</script>

<template>
  <van-pull-refresh v-model="pullLoading" :success-duration="0" @refresh="onPullRefresh">
    <div class="page" :class="packClass">
      <LogMd3
        v-if="theme.themePack === ThemePack.Md3"
        :lines="visibleLogLines"
        :level-filter="levelFilter"
        :filter-active="filterActive"
        @update:level-filter="levelFilter = $event"
        @refresh="onButtonRefresh"
        @clear="onClear"
      />
      <LogMiuix
        v-else-if="theme.themePack === ThemePack.Miuix"
        :lines="visibleLogLines"
        :level-filter="levelFilter"
        :filter-active="filterActive"
        @update:level-filter="levelFilter = $event"
        @refresh="onButtonRefresh"
        @clear="onClear"
      />
      <LogDefault
        v-else
        :lines="visibleLogLines"
        :level-filter="levelFilter"
        :filter-active="filterActive"
        @update:level-filter="levelFilter = $event"
        @refresh="onButtonRefresh"
        @clear="onClear"
      />
    </div>
  </van-pull-refresh>
</template>

<style scoped lang="scss">
.page {
  min-height: calc(100dvh - 56px - var(--qsc-inset-top, 0px) - var(--dock-pad, 72px));
}

:deep(.van-pull-refresh) {
  overflow: clip;
}

:deep(.van-pull-refresh__track) {
  will-change: auto;
}
</style>
