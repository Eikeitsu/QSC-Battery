<script setup lang="ts">
import { useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const ShortcutsCard = lazyComponent(() => import("./ui/ShortcutsCard.vue"));
const GuideCard = lazyComponent(() => import("./ui/GuideCard.vue"));

const { packClass } = useThemePackClass();
</script>

<template>
  <div class="page" :class="packClass">
    <ShortcutsCard />
    <GuideCard />
  </div>
</template>
