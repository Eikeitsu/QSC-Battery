<script setup lang="ts">
import type { ChipOption } from "../shared";

withDefaults(
  defineProps<{
    options?: ChipOption[];
    modelValue?: string | number;
  }>(),
  {
    options: () => [],
    modelValue: "",
  },
);

defineEmits<{
  "update:modelValue": [id: string | number];
}>();
</script>

<template>
  <div class="chip-row">
    <button
      v-for="opt in options"
      :key="opt.id"
      type="button"
      class="chip"
      :class="{ active: String(modelValue) === String(opt.id) }"
      @click="$emit('update:modelValue', opt.id)"
    >
      {{ opt.l }}
    </button>
  </div>
</template>

<style scoped lang="scss">
.chip-row {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  padding: 4px 0 8px;
}

.chip {
  border: none;
  border-radius: 999px;
  padding: 7px 14px;
  font-size: 13px;
  background: var(--qsc-chip-bg);
  color: var(--qsc-text-2);
  transition:
    transform 0.15s ease,
    background 0.15s ease,
    color 0.15s ease;

  &:active {
    transform: scale(0.96);
  }

  &.active {
    background: var(--qsc-primary);
    color: #fff;
    font-weight: 600;
  }
}
</style>
