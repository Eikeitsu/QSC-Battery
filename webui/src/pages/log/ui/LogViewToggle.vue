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
  display: inline-flex;
  gap: 2px;
  padding: 2px;
  border-radius: 8px;
  background: var(--qsc-chip-bg, var(--qsc-surface-2));
}

.btn {
  border: none;
  background: transparent;
  color: var(--qsc-text-2);
  font-size: 12px;
  padding: 5px 10px;
  border-radius: 6px;
  font-weight: 550;
}

.btn.active {
  background: var(--qsc-surface);
  color: var(--qsc-primary);
  font-weight: 700;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
}
</style>
