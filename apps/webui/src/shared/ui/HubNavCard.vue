<script setup lang="ts">
import { inject } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import type { SubRouteName as SubName } from "@/shared";

export interface NavItem {
  name: SubName;
  title: string;
  label: string;
}

defineProps<{
  title?: string;
  hint?: string;
  items: NavItem[];
}>();

const openSub = inject<(name: SubName) => void>("openSub", () => undefined);
</script>

<template>
  <SectionHead :title="title || '更多'" :hint="hint || ''" />
  <ThemedCard>
    <van-cell
      v-for="item in items"
      :key="item.name"
      :title="item.title"
      :label="item.label"
      is-link
      @click="openSub(item.name)"
    />
  </ThemedCard>
</template>
