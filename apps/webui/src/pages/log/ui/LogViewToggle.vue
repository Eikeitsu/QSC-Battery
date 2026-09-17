<script setup lang="ts">
defineProps<{
  modelValue: "flat" | "session";
}>();

defineEmits<{
  "update:modelValue": [v: "flat" | "session"];
}>();
</script>

<template>
  <div class="view-toggle" role="radiogroup" aria-label="日志视图">
    <button
      type="button"
      role="radio"
      class="btn"
      :class="{ active: modelValue === 'flat' }"
      :aria-checked="modelValue === 'flat'"
      @click="$emit('update:modelValue', 'flat')"
    >
      平铺
    </button>
    <button
      type="button"
      role="radio"
      class="btn"
      :class="{ active: modelValue === 'session' }"
      :aria-checked="modelValue === 'session'"
      @click="$emit('update:modelValue', 'session')"
    >
      会话
    </button>
  </div>
</template>

<style scoped lang="scss">
.view-toggle {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2px;
  width: 100%;
  padding: 3px;
  border-radius: 999px;
  background: var(--qsc-chip-bg, var(--qsc-surface-2));
  box-sizing: border-box;
}

.btn {
  border: none;
  background: transparent;
  color: var(--qsc-text-2);
  font-size: 12px;
  line-height: 1.2;
  padding: 7px 10px;
  border-radius: 999px;
  font-weight: 550;
  transition:
    background 0.16s ease,
    color 0.16s ease,
    box-shadow 0.16s ease;
}

.btn.active {
  background: var(--qsc-surface);
  color: var(--qsc-primary);
  font-weight: 700;
  box-shadow:
    0 1px 3px rgba(15, 18, 22, 0.1),
    inset 0 0 0 1px color-mix(in srgb, var(--qsc-text) 8%, transparent);
}

html.pack-md3 .view-toggle {
  border-radius: 12px;
  background: var(--qsc-surface-2);
  gap: 6px;
  padding: 0;
}

html.pack-md3 .btn {
  border-radius: 10px;
  padding: 8px 10px;
  background: transparent;
}

html.pack-md3 .btn.active {
  background: var(--qsc-primary-container, var(--qsc-primary-soft));
  color: var(--qsc-primary);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--qsc-primary) 28%, transparent);
}

html.pack-miuix .view-toggle {
  border-radius: 10px;
  background: color-mix(in srgb, var(--qsc-text) 6%, transparent);
  padding: 2px;
  gap: 0;
}

html.pack-miuix .btn {
  border-radius: 8px;
  padding: 8px 10px;
}

html.pack-miuix .btn.active {
  background: var(--qsc-surface);
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
}
</style>
