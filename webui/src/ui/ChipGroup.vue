<script setup lang="ts">
import type { ChipOption } from "../shared";
import { useTheme } from "../stores";

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

const theme = useTheme();
</script>

<template>
  <div class="chip-row" :data-pack="theme.themePack">
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
  border-radius: var(--qsc-chip-radius, 999px);
  padding: 7px 14px;
  font-size: 13px;
  background: var(--qsc-chip-bg);
  color: var(--qsc-text-2);
  transition:
    transform 0.15s ease,
    background 0.15s ease,
    color 0.15s ease,
    box-shadow 0.15s ease;

  &:active {
    transform: scale(0.96);
  }

  &.active {
    background: var(--qsc-primary);
    color: var(--qsc-on-primary, #fff);
    font-weight: 600;
  }
}

.chip-row[data-pack="md3"] .chip.active {
  background: var(--qsc-primary-container, var(--qsc-primary-soft));
  color: var(--qsc-primary);
  font-weight: 650;
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--qsc-primary) 28%, transparent);
}

.chip-row[data-pack="miuix"] .chip {
  border-radius: 12px;
}

.chip-row[data-pack="miuix"] .chip.active {
  background: var(--qsc-primary);
  color: var(--qsc-on-primary, #fff);
}
</style>
