<script setup lang="ts">
import BatteryGlyph from "@/shared/ui/BatteryGlyph.vue";
import { useBatteryInfo } from "@/composables";
import { useAppStore } from "@/stores";

const store = useAppStore();
const { charging, badgeType } = useBatteryInfo();
</script>

<template>
  <section class="hero card">
    <div class="hero-glow"></div>
    <div class="metrics">
      <div class="metric metric--batt">
        <div class="metric__batt-row">
          <BatteryGlyph
            :level="store.status.level"
            :charging="charging"
            :size="52"
            variant="hero"
          />
          <div class="value">{{ store.status.level }}</div>
        </div>
        <div class="label">电量 %</div>
      </div>
      <div class="divider"></div>
      <div class="metric">
        <div class="value">{{ store.status.temp }}</div>
        <div class="label">温度 °C</div>
      </div>
    </div>
    <div class="status-row">
      <van-tag round :type="badgeType(String(store.status.badgeType))">
        {{ store.status.badge }}
      </van-tag>
      <span class="updated">{{ store.status.updatedAt }}</span>
    </div>
    <p class="desc">{{ store.status.desc }}</p>
  </section>
</template>

<style scoped lang="scss">
.hero {
  position: relative;
  overflow: hidden;
}

.hero-glow {
  position: absolute;
  inset: -40% -20% auto;
  height: 140%;
  background: radial-gradient(closest-side, var(--qsc-hero-glow), transparent 70%);
  pointer-events: none;
}

.metrics {
  position: relative;
  display: flex;
  align-items: stretch;
  margin-bottom: 12px;
}

.metric {
  flex: 1;
}

.metric__batt-row {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.metric .value {
  font-size: 40px;
  font-weight: 760;
  letter-spacing: -1px;
  line-height: 1.05;
  font-variant-numeric: tabular-nums;
}

.metric .label {
  margin-top: 6px;
  font-size: 12px;
  color: var(--qsc-text-3);
}

.divider {
  width: 1px;
  margin: 8px 12px;
  background: color-mix(in srgb, var(--qsc-hairline) 90%, transparent);
}

.status-row {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 10px;
}

.updated {
  font-size: 11px;
  color: var(--qsc-text-3);
  font-variant-numeric: tabular-nums;
}

.desc {
  position: relative;
  margin: 0;
  font-size: 13px;
  color: var(--qsc-text-2);
  line-height: 1.45;
}
</style>
