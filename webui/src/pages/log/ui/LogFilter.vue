<script setup lang="ts">
import { LOG_LEVEL_PRESETS, LogLevel } from "@/shared";
import { useTheme } from "@/stores";

defineProps<{
  modelValue: string;
}>();

defineEmits<{
  "update:modelValue": [id: string];
}>();

const theme = useTheme();

const TONE: Record<string, string> = {
  "": "all",
  [LogLevel.Info]: "info",
  [LogLevel.Warn]: "warn",
  [LogLevel.Error]: "error",
  [LogLevel.Debug]: "debug",
};
</script>

<template>
  <div
    class="log-filter"
    :data-pack="theme.themePack"
    role="radiogroup"
    aria-label="日志等级"
  >
    <button
      v-for="opt in LOG_LEVEL_PRESETS"
      :key="opt.id === '' ? '__all' : opt.id"
      type="button"
      role="radio"
      class="seg"
      :class="[`tone-${TONE[opt.id] || 'all'}`, { active: modelValue === opt.id }]"
      :aria-checked="modelValue === opt.id"
      @click="$emit('update:modelValue', opt.id)"
    >
      <i class="dot" aria-hidden="true"></i>
      <span>{{ opt.l }}</span>
    </button>
  </div>
</template>

<style scoped lang="scss">
.log-filter {
  display: flex;
  gap: 6px;
  margin: 8px 0 12px;
  overflow-x: auto;
  scrollbar-width: none;
  -webkit-overflow-scrolling: touch;

  &::-webkit-scrollbar {
    display: none;
  }
}

.seg {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 5px;
  min-width: 0;
  border: none;
  padding: 6px 10px;
  font-size: 12px;
  line-height: 1.2;
  font-weight: 550;
  white-space: nowrap;
  color: var(--qsc-text-2);
  background: transparent;
  transition:
    background 0.16s ease,
    color 0.16s ease,
    box-shadow 0.16s ease,
    transform 0.12s ease;

  &:active {
    transform: scale(0.97);
  }
}

.dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
  background: currentcolor;
  opacity: 0.45;
}

.seg.active .dot {
  opacity: 1;
}

.tone-all .dot {
  background: var(--qsc-text-3);
}

.tone-info .dot {
  background: var(--qsc-success);
}

.tone-warn .dot {
  background: var(--qsc-warn);
}

.tone-error .dot {
  background: var(--qsc-danger);
}

.tone-debug .dot {
  background: var(--qsc-text-3);
}

/* —— 默认：胶囊轨道 + 色点 —— */
.log-filter[data-pack="default"] {
  background: var(--qsc-chip-bg);
  border-radius: 999px;
  padding: 3px;
  gap: 2px;
}

.log-filter[data-pack="default"] .seg {
  flex: 1 1 0;
  border-radius: 999px;
  padding: 7px 4px;
  background: transparent;
}

.log-filter[data-pack="default"] .seg.active {
  background: var(--qsc-surface);
  color: var(--qsc-text);
  font-weight: 700;
  box-shadow:
    0 1px 3px rgba(15, 18, 22, 0.12),
    inset 0 0 0 1px color-mix(in srgb, var(--qsc-text) 8%, transparent);
}

.log-filter[data-pack="default"] .seg.active.tone-info {
  color: var(--qsc-success);
}

.log-filter[data-pack="default"] .seg.active.tone-warn {
  color: var(--qsc-warn);
}

.log-filter[data-pack="default"] .seg.active.tone-error {
  color: var(--qsc-danger);
}

.log-filter[data-pack="default"] .seg.active.tone-debug {
  color: var(--qsc-text-2);
}

.log-filter[data-pack="default"] .seg.active.tone-all {
  color: var(--qsc-primary);
}

/* —— MD3：色调 chips —— */
.log-filter[data-pack="md3"] {
  gap: 8px;
  margin: 10px 0 4px;
}

.log-filter[data-pack="md3"] .seg {
  flex: 1 1 0;
  border-radius: 10px;
  padding: 8px 6px;
  background: var(--qsc-surface-2);
  color: var(--qsc-text-2);
}

.log-filter[data-pack="md3"] .seg.active {
  font-weight: 700;
}

.log-filter[data-pack="md3"] .seg.active.tone-all,
.log-filter[data-pack="md3"] .seg.active.tone-info {
  background: var(--qsc-primary-container, var(--qsc-primary-soft));
  color: var(--qsc-primary);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--qsc-primary) 28%, transparent);
}

.log-filter[data-pack="md3"] .seg.active.tone-warn {
  background: color-mix(in srgb, var(--qsc-warn) 16%, var(--qsc-surface));
  color: var(--qsc-warn);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--qsc-warn) 32%, transparent);
}

.log-filter[data-pack="md3"] .seg.active.tone-error {
  background: color-mix(in srgb, var(--qsc-danger) 14%, var(--qsc-surface));
  color: var(--qsc-danger);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--qsc-danger) 30%, transparent);
}

.log-filter[data-pack="md3"] .seg.active.tone-debug {
  background: color-mix(in srgb, var(--qsc-text) 8%, var(--qsc-surface-2));
  color: var(--qsc-text);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--qsc-text) 14%, transparent);
}

/* —— MIUIX：分段控件 —— */
.log-filter[data-pack="miuix"] {
  margin: 0;
  background: color-mix(in srgb, var(--qsc-text) 6%, transparent);
  border-radius: 10px;
  padding: 2px;
  gap: 0;
}

.log-filter[data-pack="miuix"] .seg {
  flex: 1 1 0;
  border-radius: 8px;
  padding: 8px 2px;
  font-size: 12px;
  font-weight: 500;
}

.log-filter[data-pack="miuix"] .seg.active {
  background: var(--qsc-surface);
  font-weight: 650;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
}

.log-filter[data-pack="miuix"] .seg.active.tone-all {
  color: var(--qsc-primary);
}

.log-filter[data-pack="miuix"] .seg.active.tone-info {
  color: var(--qsc-success);
}

.log-filter[data-pack="miuix"] .seg.active.tone-warn {
  color: var(--qsc-warn);
}

.log-filter[data-pack="miuix"] .seg.active.tone-error {
  color: var(--qsc-danger);
}

.log-filter[data-pack="miuix"] .seg.active.tone-debug {
  color: var(--qsc-text-2);
}
</style>
