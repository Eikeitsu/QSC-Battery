<script setup lang="ts">
import BatteryGlyph from "@/shared/ui/BatteryGlyph.vue";
import { useBatteryInfo } from "@/composables";

const {
  store,
  charging,
  healthText,
  designMahText,
  fullMahText,
  sohText,
  barPct,
  hasBar,
} = useBatteryInfo();
</script>

<template>
  <section class="md3-tonal md3-batt">
    <div class="md3-batt__head">
      <div class="md3-batt__title-row">
        <BatteryGlyph
          :level="store.status.level"
          :charging="charging"
          :size="28"
          variant="md3"
        />
        <div class="md3-batt__title">电池健康</div>
      </div>
      <div class="md3-batt__soh">
        <span class="md3-batt__soh-num">{{ sohText }}</span>
        <span class="md3-batt__soh-label">健康度</span>
      </div>
    </div>

    <div class="md3-batt__bar" :class="{ 'is-empty': !hasBar }" aria-hidden="true">
      <div class="md3-batt__bar-fill" :style="{ width: `${barPct}%` }"></div>
    </div>

    <div class="md3-batt__meta">
      <div class="md3-batt__chip">
        <div class="md3-batt__k">状态</div>
        <div class="md3-batt__v">{{ healthText }}</div>
      </div>
      <div class="md3-batt__chip">
        <div class="md3-batt__k">额定容量</div>
        <div class="md3-batt__v">{{ designMahText }}</div>
      </div>
      <div class="md3-batt__chip">
        <div class="md3-batt__k">满充容量</div>
        <div class="md3-batt__v">{{ fullMahText }}</div>
      </div>
      <div class="md3-batt__chip">
        <div class="md3-batt__k">循环计数</div>
        <div class="md3-batt__v">{{ store.status.cycleCount }}</div>
      </div>
    </div>
  </section>
</template>

<style scoped lang="scss">
.md3-batt {
  padding: 16px 18px 14px;
}

.md3-batt__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.md3-batt__title-row {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.md3-batt__title {
  font-size: 15px;
  font-weight: 600;
}

.md3-batt__soh {
  text-align: right;
  flex-shrink: 0;
}

.md3-batt__soh-num {
  display: block;
  font-size: 28px;
  font-weight: 650;
  letter-spacing: -0.5px;
  line-height: 1.1;
  font-variant-numeric: tabular-nums;
  color: var(--qsc-primary);
}

.md3-batt__soh-label {
  display: block;
  margin-top: 2px;
  font-size: 11px;
  color: var(--qsc-text-3);
}

.md3-batt__bar {
  margin-top: 12px;
  height: 6px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--qsc-primary) 14%, var(--qsc-surface-2));
  overflow: hidden;

  &.is-empty .md3-batt__bar-fill {
    opacity: 0.25;
  }
}

.md3-batt__bar-fill {
  height: 100%;
  border-radius: inherit;
  background: var(--qsc-primary);
  transition: width 0.45s ease;
}

.md3-batt__meta {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px 12px;
  margin-top: 14px;
}

.md3-batt__k {
  font-size: 11px;
  color: var(--qsc-text-3);
}

.md3-batt__v {
  margin-top: 2px;
  font-size: 13px;
  font-weight: 550;
  color: var(--qsc-text);
  font-variant-numeric: tabular-nums;
}
</style>
