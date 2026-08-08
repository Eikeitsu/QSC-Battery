<script setup lang="ts">
import { useAppStore } from "@/stores";

defineEmits<{
  openConfig: [];
}>();

const store = useAppStore();
</script>

<template>
  <section class="md3-tonal md3-strategy" @click="$emit('openConfig')">
    <div class="md3-strategy__head">
      <span class="md3-strategy__title">当前策略</span>
      <span class="md3-strategy__go">调整</span>
    </div>
    <div class="md3-list">
      <div class="md3-list__row">
        <span class="md3-list__k">电量停充</span>
        <span class="md3-list__v">{{ store.powerPlan }}</span>
      </div>
      <div class="md3-list__row">
        <span class="md3-list__k">温控停充</span>
        <span class="md3-list__v">{{ store.tempPlan }}</span>
      </div>
      <div class="md3-list__row">
        <span class="md3-list__k">充满再停</span>
        <span class="md3-list__v">{{ store.fullPlan }}</span>
      </div>
      <div class="md3-list__row">
        <span class="md3-list__k">兼容模式</span>
        <span class="md3-list__v">{{ store.compatPlan }}</span>
      </div>
      <div v-if="store.currentFeature" class="md3-list__row">
        <span class="md3-list__k">电流控制</span>
        <span class="md3-list__v">{{ store.currentPlan }}</span>
      </div>
    </div>
  </section>
</template>

<style scoped lang="scss">
.md3-strategy {
  padding: 4px 0 8px;
  cursor: pointer;

  &:active {
    opacity: 0.92;
  }
}

.md3-strategy__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 18px 6px;
}

.md3-strategy__title {
  font-size: 15px;
  font-weight: 600;
}

.md3-strategy__go {
  font-size: 13px;
  font-weight: 600;
  color: var(--qsc-primary);
}

.md3-list__row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 18px;
  border-top: 1px solid var(--qsc-hairline);
}

.md3-list__k {
  font-size: 14px;
  color: var(--qsc-text);
}

.md3-list__v {
  font-size: 13px;
  color: var(--qsc-text-2);
  text-align: right;
}
</style>
