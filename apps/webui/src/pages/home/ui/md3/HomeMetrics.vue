<script setup lang="ts">
import BatteryGlyph from "@/shared/ui/BatteryGlyph.vue";
import { useBatteryInfo } from "@/composables";

const { store, charging } = useBatteryInfo();
</script>

<template>
  <div class="md3-metrics">
    <section class="md3-tonal md3-metric">
      <div class="md3-metric__top">
        <BatteryGlyph
          :level="store.status.level"
          :charging="charging"
          :size="26"
          variant="md3"
        />
      </div>
      <div class="md3-metric__value">{{ store.status.level }}</div>
      <div class="md3-metric__label">电量 %</div>
    </section>
    <section class="md3-tonal md3-metric">
      <div class="md3-metric__value md3-metric__value--solo">{{ store.status.temp }}</div>
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
  padding: 14px 14px 16px;
}

.md3-metric__top {
  margin-bottom: 8px;
  min-height: 16px;
}

.md3-metric__value {
  font-size: 32px;
  font-weight: 650;
  letter-spacing: -0.5px;
  line-height: 1.1;
  font-variant-numeric: tabular-nums;

  &--solo {
    margin-top: 24px;
  }
}

.md3-metric__label {
  margin-top: 6px;
  font-size: 12px;
  color: var(--qsc-text-2);
}
</style>
