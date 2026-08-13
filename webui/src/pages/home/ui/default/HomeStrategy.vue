<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import { useStrategyRows } from "@/composables";

defineEmits<{
  openConfig: [];
}>();

const rows = useStrategyRows();
</script>

<template>
  <SectionHead title="当前策略" hint="点按可前往策略页调整" />
  <section class="card strategy" @click="$emit('openConfig')">
    <div v-for="row in rows" :key="row.id" class="strategy-row">
      <span class="k">{{ row.label }}</span>
      <span class="v">{{ row.value }}</span>
    </div>
    <div class="go">前往策略 →</div>
  </section>
</template>

<style scoped lang="scss">
.strategy {
  padding: 6px 4px 10px;
  cursor: pointer;

  &:active {
    transform: scale(0.985);
    background: var(--qsc-press);
  }
}

.strategy-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  font-size: 13px;
}

.strategy-row .k {
  color: var(--qsc-text-2);
  flex-shrink: 0;
}

.strategy-row .v {
  color: var(--qsc-text);
  text-align: right;
  font-weight: 550;
}

.go {
  padding: 4px 14px 6px;
  font-size: 12px;
  font-weight: 650;
  color: var(--qsc-primary);
}
</style>
