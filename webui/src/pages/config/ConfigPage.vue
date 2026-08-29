<script setup lang="ts">
import { provideConfigForm, useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const PowerStopCard = lazyComponent(() => import("./ui/PowerStopCard.vue"));
const StopBehaviorCard = lazyComponent(() => import("./ui/StopBehaviorCard.vue"));
const TempStopCard = lazyComponent(() => import("./ui/TempStopCard.vue"));
const CurrentControlCard = lazyComponent(() => import("./ui/CurrentControlCard.vue"));
const AdvancedRuntimeCard = lazyComponent(() => import("./ui/AdvancedRuntimeCard.vue"));
const PreferredCard = lazyComponent(() => import("./ui/PreferredCard.vue"));
const PowerSwitchCard = lazyComponent(() => import("./ui/PowerSwitchCard.vue"));
const SwitchToolsCard = lazyComponent(() => import("./ui/SwitchToolsCard.vue"));
const DaemonCard = lazyComponent(() => import("./ui/DaemonCard.vue"));

const { packClass } = useThemePackClass();
provideConfigForm();
</script>

<template>
  <div class="page" :class="packClass">
    <PowerStopCard />
    <StopBehaviorCard />
    <TempStopCard />
    <CurrentControlCard />
    <PreferredCard />
    <PowerSwitchCard />
    <SwitchToolsCard />
    <AdvancedRuntimeCard />
    <DaemonCard />
  </div>
</template>
