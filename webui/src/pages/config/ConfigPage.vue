<script setup lang="ts">
import { provideConfigForm, useThemePackClass } from "@/composables";
import PowerStopCard from "./ui/PowerStopCard.vue";
import StopBehaviorCard from "./ui/StopBehaviorCard.vue";
import TempStopCard from "./ui/TempStopCard.vue";
import CurrentControlCard from "./ui/CurrentControlCard.vue";
import AdvancedRuntimeCard from "./ui/AdvancedRuntimeCard.vue";
import PreferredCard from "./ui/PreferredCard.vue";
import PowerSwitchCard from "./ui/PowerSwitchCard.vue";
import SwitchToolsCard from "./ui/SwitchToolsCard.vue";

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
  </div>
</template>
