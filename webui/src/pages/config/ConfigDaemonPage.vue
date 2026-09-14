<script setup lang="ts">
import { provideConfigForm, useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const DaemonCard = lazyComponent(() => import("./ui/DaemonCard.vue"));

const { packClass } = useThemePackClass();
provideConfigForm();
</script>

<template>
  <div class="page" :class="packClass">
    <DaemonCard />
  </div>
</template>
