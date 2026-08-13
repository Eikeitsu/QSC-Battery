<script setup lang="ts">
import { computed } from "vue";
import { DOCK_CLASS, TABS, dockIconsForPack, type TabName } from "@/shared";
import { useTheme } from "@/stores";

defineProps<{
  tab: TabName;
}>();

defineEmits<{
  "update:tab": [name: string | number];
}>();

const theme = useTheme();
const dockIcons = computed(() => dockIconsForPack(theme.themePack));
</script>

<template>
  <van-tabbar
    class="app-dock"
    :class="DOCK_CLASS[theme.themePack]"
    :model-value="tab"
    :safe-area-inset-bottom="false"
    active-color="var(--qsc-primary)"
    inactive-color="var(--qsc-text-3)"
    @update:model-value="$emit('update:tab', $event)"
  >
    <van-tabbar-item
      v-for="item in TABS"
      :key="item.name"
      :name="item.name"
      :icon="dockIcons[item.name]"
    >
      {{ item.label }}
    </van-tabbar-item>
  </van-tabbar>
</template>
