<script setup lang="ts">
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import { useAppStore } from "@/stores";

const store = useAppStore();
</script>

<template>
  <section class="card switch-card">
    <SwitchCell
      title="模块总开关"
      label="关闭后不再自动停充 / 恢复"
      :model-value="store.status.moduleOn"
      @update:model-value="store.toggleModule"
    />
  </section>
</template>

<style scoped lang="scss">
.switch-card {
  margin-top: 12px;
}
</style>
