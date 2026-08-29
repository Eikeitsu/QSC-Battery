<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { DOCK_CLASS, TABS, dockIconsForPack, isTabName, type TabName } from "@/shared";
import { useTheme } from "@/stores";

const props = defineProps<{
  tab: TabName;
}>();

const emit = defineEmits<{
  "update:tab": [name: string | number];
}>();

const theme = useTheme();
const dockIcons = computed(() => dockIconsForPack(theme.themePack));
const selectedTab = ref<TabName>(props.tab);

watch(
  () => props.tab,
  (value) => {
    selectedTab.value = value;
  },
);

function onTabUpdate(value: string | number) {
  const next = String(value);
  if (!isTabName(next)) return;
  selectedTab.value = next;
  emit("update:tab", next);
}
</script>

<template>
  <van-tabbar
    class="app-dock"
    :class="DOCK_CLASS[theme.themePack]"
    :model-value="selectedTab"
    :safe-area-inset-bottom="false"
    active-color="var(--qsc-primary)"
    inactive-color="var(--qsc-text-3)"
    @update:model-value="onTabUpdate"
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
