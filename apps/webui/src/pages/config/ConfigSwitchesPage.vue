<script setup lang="ts">
import { provideConfigForm, useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const PreferredCard = lazyComponent(() => import("./ui/PreferredCard.vue"));
const PowerSwitchCard = lazyComponent(() => import("./ui/PowerSwitchCard.vue"));
const SwitchToolsCard = lazyComponent(() => import("./ui/SwitchToolsCard.vue"));

const { packClass } = useThemePackClass();
provideConfigForm();
</script>

<template>
  <div class="page" :class="packClass">
    <PreferredCard />
    <PowerSwitchCard />
    <SwitchToolsCard />
  </div>
</template>
