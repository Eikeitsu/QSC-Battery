<script setup lang="ts">
import { formatMah, healthLabel, parsePercent } from "@/shared/lib/batteryDisplay";
import { useAppStore } from "@/stores";
import { computed } from "vue";

const store = useAppStore();

const sohText = computed(() => {
  const n = parsePercent(store.status.soh);
  return n !== null ? `${n}%` : "--";
});
</script>

<template>
  <section class="miuix-card miuix-batt">
    <div class="miuix-batt__row">
      <span>电池健康</span>
      <b>{{ healthLabel(store.status.health) }}</b>
    </div>
    <div class="miuix-batt__row">
      <span>预估健康度</span>
      <b>{{ sohText }}</b>
    </div>
    <div class="miuix-batt__row">
      <span>设计容量</span>
      <b>{{ formatMah(store.status.designMah) }}</b>
    </div>
    <div class="miuix-batt__row">
      <span>当前满充</span>
      <b>{{ formatMah(store.status.fullMah) }}</b>
    </div>
    <div class="miuix-batt__row">
      <span>循环次数</span>
      <b>{{ store.status.cycleCount }}</b>
    </div>
  </section>
</template>

<style scoped lang="scss">
.miuix-batt {
  padding: 4px 0;
}

.miuix-batt__row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  padding: 13px 14px;
  font-size: 15px;
  border-bottom: 1px solid var(--qsc-hairline);

  &:last-child {
    border-bottom: none;
  }

  span {
    color: var(--qsc-text);
    flex-shrink: 0;
  }

  b {
    font-weight: 550;
    color: var(--qsc-text-2);
    text-align: right;
    font-variant-numeric: tabular-nums;
    word-break: break-all;
  }
}
</style>
