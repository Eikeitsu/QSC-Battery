<script setup lang="ts">
import { useAppStore } from "@/stores";

defineEmits<{
  openConfig: [];
}>();

const store = useAppStore();
</script>

<template>
  <section class="miuix-card miuix-strategy" @click="$emit('openConfig')">
    <div class="miuix-pref">
      <div class="miuix-pref__body">
        <div class="miuix-pref__title">电量停充</div>
        <div class="miuix-pref__desc">{{ store.powerPlan }}</div>
      </div>
      <span class="miuix-pref__arrow">›</span>
    </div>
    <div class="miuix-pref">
      <div class="miuix-pref__body">
        <div class="miuix-pref__title">温控停充</div>
        <div class="miuix-pref__desc">{{ store.tempPlan }}</div>
      </div>
      <span class="miuix-pref__arrow">›</span>
    </div>
    <div class="miuix-pref">
      <div class="miuix-pref__body">
        <div class="miuix-pref__title">充满再停</div>
        <div class="miuix-pref__desc">{{ store.fullPlan }}</div>
      </div>
      <span class="miuix-pref__arrow">›</span>
    </div>
    <div class="miuix-pref">
      <div class="miuix-pref__body">
        <div class="miuix-pref__title">兼容模式</div>
        <div class="miuix-pref__desc">{{ store.compatPlan }}</div>
      </div>
      <span class="miuix-pref__arrow">›</span>
    </div>
    <div v-if="store.currentFeature" class="miuix-pref">
      <div class="miuix-pref__body">
        <div class="miuix-pref__title">电流控制</div>
        <div class="miuix-pref__desc">{{ store.currentPlan }}</div>
      </div>
      <span class="miuix-pref__arrow">›</span>
    </div>
  </section>
</template>

<style scoped lang="scss">
.miuix-strategy {
  overflow: hidden;
  cursor: pointer;
}

.miuix-pref {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 14px;
  border-bottom: 1px solid var(--qsc-hairline);

  &:last-child {
    border-bottom: none;
  }

  &:active {
    background: var(--qsc-press);
  }
}

.miuix-pref__body {
  flex: 1;
  min-width: 0;
}

.miuix-pref__title {
  font-size: 16px;
}

.miuix-pref__desc {
  margin-top: 2px;
  font-size: 12px;
  color: var(--qsc-text-3);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.miuix-pref__arrow {
  color: var(--qsc-text-3);
  font-size: 20px;
  line-height: 1;
}
</style>
