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
  <section class="md3-tonal md3-info">
    <div class="md3-info__item">
      <div class="md3-info__k">充电状态</div>
      <div class="md3-info__v">{{ store.status.chargeLabel }}</div>
    </div>
    <div class="md3-info__item">
      <div class="md3-info__k">电压</div>
      <div class="md3-info__v">{{ store.status.voltage }} V</div>
    </div>
    <div class="md3-info__item">
      <div class="md3-info__k">电流</div>
      <div class="md3-info__v">{{ store.status.currentMa }} mA</div>
    </div>
    <div class="md3-info__item">
      <div class="md3-info__k">电池健康</div>
      <div class="md3-info__v">{{ healthText }}</div>
    </div>
    <div class="md3-info__item">
      <div class="md3-info__k">设计容量</div>
      <div class="md3-info__v">
        {{ store.status.designMah === "--" ? "--" : `${store.status.designMah} mAh` }}
      </div>
    </div>
    <div class="md3-info__item">
      <div class="md3-info__k">真实容量</div>
      <div class="md3-info__v">
        {{ store.status.fullMah === "--" ? "--" : `${store.status.fullMah} mAh` }}
      </div>
    </div>
    <div class="md3-info__item">
      <div class="md3-info__k">循环次数</div>
      <div class="md3-info__v">{{ store.status.cycleCount }}</div>
    </div>
    <div class="md3-info__item">
      <div class="md3-info__k">版本</div>
      <div class="md3-info__v">{{ store.status.version }}</div>
    </div>
  </section>
</template>

<style scoped lang="scss">
.md3-info {
  padding: 8px 18px 12px;
}

.md3-info__item {
  padding: 12px 0;
  border-bottom: 1px solid var(--qsc-hairline);

  &:last-child {
    border-bottom: none;
  }
}

.md3-info__k {
  font-size: 15px;
  font-weight: 500;
}

.md3-info__v {
  margin-top: 2px;
  font-size: 13px;
  color: var(--qsc-text-2);
}
</style>
