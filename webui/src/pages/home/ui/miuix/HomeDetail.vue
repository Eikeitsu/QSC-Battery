<script setup lang="ts">
import { computed } from "vue";
import { useAppStore } from "@/stores";

const store = useAppStore();

const healthText = computed(() => {
  const h = store.status.health;
  const soh = store.status.soh;
  const parts: string[] = [];
  if (h && h !== "--") parts.push(h);
  if (soh && soh !== "--") parts.push(`SOH ${soh}%`);
  return parts.length ? parts.join(" · ") : "--";
});
</script>

<template>
  <section class="miuix-card miuix-detail">
    <div class="miuix-detail__row">
      <span>电压</span>
      <b>{{ store.status.voltage }} V</b>
    </div>
    <div class="miuix-detail__row">
      <span>电池健康</span>
      <b>{{ healthText }}</b>
    </div>
    <div class="miuix-detail__row">
      <span>设计容量</span>
      <b>{{ store.status.designMah === "--" ? "--" : `${store.status.designMah} mAh` }}</b>
    </div>
    <div class="miuix-detail__row">
      <span>真实容量</span>
      <b>{{ store.status.fullMah === "--" ? "--" : `${store.status.fullMah} mAh` }}</b>
    </div>
    <div class="miuix-detail__row">
      <span>循环次数</span>
      <b>{{ store.status.cycleCount }}</b>
    </div>
    <div class="miuix-detail__row">
      <span>版本</span>
      <b>{{ store.status.version }}</b>
    </div>
  </section>
</template>

<style scoped lang="scss">
.miuix-detail {
  padding: 4px 0;
}

.miuix-detail__row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 13px 14px;
  font-size: 15px;
  border-bottom: 1px solid var(--qsc-hairline);

  &:last-child {
    border-bottom: none;
  }

  span {
    color: var(--qsc-text);
  }

  b {
    font-weight: 550;
    color: var(--qsc-text-2);
    text-align: right;
    max-width: 58%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
}
</style>
