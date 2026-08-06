<script setup lang="ts">
import { useAppStore } from "../../stores";

const store = useAppStore();
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
