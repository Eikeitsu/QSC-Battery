<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { DOCK_CLASS, TABS, dockIconsForPack, type TabName } from "@/shared";
import { useTheme } from "@/stores";

const props = defineProps<{
  tab: TabName;
}>();

const emit = defineEmits<{
  "update:tab": [name: string | number];
}>();

const theme = useTheme();
const dockIcons = computed(() => dockIconsForPack(theme.themePack));
const localTab = ref<TabName>(props.tab);

watch(
  () => props.tab,
  (value) => {
    localTab.value = value;
  },
);

function previewTab(name: string | number) {
  if (typeof name === "string") localTab.value = name as TabName;
}

function selectTab(name: string | number) {
  previewTab(name);
  emit("update:tab", name);
}
</script>

<template>
  <van-tabbar
    class="app-dock"
    :class="DOCK_CLASS[theme.themePack]"
    :model-value="localTab"
    :safe-area-inset-bottom="false"
    active-color="var(--qsc-primary)"
    inactive-color="var(--qsc-text-3)"
    @update:model-value="selectTab"
  >
    <van-tabbar-item
      v-for="item in TABS"
      :key="item.name"
      :name="item.name"
      :icon="dockIcons[item.name]"
      @pointerdown="previewTab(item.name)"
      @click="previewTab(item.name)"
    >
      {{ item.label }}
    </van-tabbar-item>
  </van-tabbar>
</template>
