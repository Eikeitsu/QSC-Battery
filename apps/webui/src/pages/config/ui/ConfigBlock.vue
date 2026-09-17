<script setup lang="ts">
withDefaults(
  defineProps<{
    label?: string;
    hint?: string;
    nested?: boolean;
  }>(),
  {
    label: "",
    hint: "",
    nested: false,
  },
);
</script>

<template>
  <div class="block" :class="{ nested }">
    <div v-if="label" class="block-label">{{ label }}</div>
    <slot></slot>
    <p v-if="hint" class="field-hint">{{ hint }}</p>
  </div>
</template>

<style scoped lang="scss">
.block {
  padding: 12px var(--qsc-cell-pad-x, 16px) 8px;
}

.block.nested {
  padding-top: 4px;
}

.block-label {
  font-size: 13px;
  color: var(--qsc-text-2);
  margin: 6px 0 2px;
}

.field-hint {
  margin: 4px 0 8px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.4;
}
</style>
