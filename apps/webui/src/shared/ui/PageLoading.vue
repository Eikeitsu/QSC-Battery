<script setup lang="ts">
withDefaults(
  defineProps<{
    text?: string;
  }>(),
  {
    text: "正在加载…",
  },
);
</script>

<template>
  <div class="page-loading" role="status" aria-live="polite">
    <span class="page-loading__spinner" aria-hidden="true"></span>
    <span>{{ text }}</span>
  </div>
</template>

<style scoped lang="scss">
.page-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 64px;
  padding: 16px;
  color: var(--qsc-text-2);
  font-size: 13px;
}

.page-loading__spinner {
  width: 16px;
  height: 16px;
  border: 2px solid color-mix(in srgb, var(--qsc-primary) 22%, transparent);
  border-top-color: var(--qsc-primary);
  border-radius: 50%;
  animation: page-loading-spin 0.8s linear infinite;
}

@keyframes page-loading-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
