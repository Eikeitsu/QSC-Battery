<script setup lang="ts">
import { useAppStore } from "@/stores";

const store = useAppStore();
</script>

<template>
  <div class="md3-metrics">
    <section class="md3-tonal md3-metric">
      <div class="md3-metric__value">{{ store.status.level }}</div>
      <div class="md3-metric__label">电量 %</div>
    </section>
    <section class="md3-tonal md3-metric">
      <div class="md3-metric__value">{{ store.status.temp }}</div>
      <div class="md3-metric__label">温度 °C</div>
    </section>
  </div>
</template>

<style scoped lang="scss">
.md3-metrics {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.md3-metric {
  padding: 16px 14px;
}

.md3-metric__value {
  font-size: 32px;
  font-weight: 650;
  letter-spacing: -0.5px;
  line-height: 1.1;
  font-variant-numeric: tabular-nums;
}

.md3-metric__label {
  margin-top: 6px;
  font-size: 12px;
  color: var(--qsc-text-2);
}
</style>
