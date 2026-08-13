<script setup lang="ts">
import { THEME_DEFAULTS } from "@/shared";

defineProps<{
  seed: string;
  seedHex: string;
}>();

defineEmits<{
  pick: [];
  commit: [];
  "update:seedHex": [v: string];
}>();
</script>

<template>
  <div class="pad seed-panel">
    <button type="button" class="seed-swatch" @click="$emit('pick')">
      <span class="seed-swatch__dot" :style="{ background: seed }"></span>
      <span>点此取色</span>
    </button>
    <van-field
      :model-value="seedHex"
      label="色值"
      :placeholder="THEME_DEFAULTS.md3Seed"
      input-align="right"
      maxlength="7"
      @update:model-value="$emit('update:seedHex', String($event || ''))"
      @change="$emit('commit')"
      @blur="$emit('commit')"
    />
  </div>
</template>

<style scoped lang="scss">
.pad {
  padding: 0 16px 10px;
}

.seed-panel {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding-bottom: 14px;
}

.seed-swatch {
  display: flex;
  align-items: center;
  gap: 10px;
  border: none;
  border-radius: 12px;
  padding: 10px 12px;
  background: var(--qsc-surface-2, var(--qsc-chip-bg));
  color: var(--qsc-text);
  font-size: 13px;
  text-align: left;
}

.seed-swatch__dot {
  width: 28px;
  height: 28px;
  border-radius: 8px;
  border: 1px solid var(--qsc-hairline);
  flex-shrink: 0;
}
</style>
