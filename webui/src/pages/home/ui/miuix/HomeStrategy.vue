<script setup lang="ts">
import { useStrategyRows } from "@/composables";

defineEmits<{
  openConfig: [];
}>();

const rows = useStrategyRows();
</script>

<template>
  <section class="miuix-card miuix-strategy" @click="$emit('openConfig')">
    <div v-for="row in rows" :key="row.id" class="miuix-pref">
      <div class="miuix-pref__body">
        <div class="miuix-pref__title">{{ row.label }}</div>
        <div class="miuix-pref__desc">{{ row.value }}</div>
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
