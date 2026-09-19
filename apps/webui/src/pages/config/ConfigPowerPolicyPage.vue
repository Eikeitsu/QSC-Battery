<script setup lang="ts">
import { provideConfigForm, useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const PowerPolicyCard = lazyComponent(() => import("./ui/PowerPolicyCard.vue"));

const { packClass } = useThemePackClass();
provideConfigForm();
</script>

<template>
  <div class="page" :class="packClass">
    <PowerPolicyCard />
  </div>
</template>
