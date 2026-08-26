<script setup lang="ts">
import { provideConfigForm, useThemePackClass } from "@/composables";
import PowerStopCard from "./ui/PowerStopCard.vue";
import TempStopCard from "./ui/TempStopCard.vue";
import PreferredCard from "./ui/PreferredCard.vue";
import PowerSwitchCard from "./ui/PowerSwitchCard.vue";
import CurrentControlCard from "./ui/CurrentControlCard.vue";

const { packClass } = useThemePackClass();
provideConfigForm();
</script>

<template>
  <div class="page" :class="packClass">
    <PowerStopCard />
    <TempStopCard />
    <PreferredCard />
    <PowerSwitchCard />
    <CurrentControlCard />
  </div>
</template>

<style scoped lang="scss">
.page-md3 {
  :deep(.section-head) {
    margin: 20px 4px 12px;
  }

  :deep(.section-head .title) {
    font-size: 13px;
    font-weight: 600;
    color: var(--qsc-text-2);
    letter-spacing: 0.02em;
  }

  :deep(.card) {
    margin-bottom: 4px;
  }
}

.page-miuix {
  :deep(.section-head) {
    margin: 16px 10px 8px;
  }

  :deep(.section-head .title) {
    font-size: 13px;
  }
}
</style>
