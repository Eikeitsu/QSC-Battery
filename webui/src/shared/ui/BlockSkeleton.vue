<script setup lang="ts">
withDefaults(
  defineProps<{
    height?: number;
  }>(),
  {
    height: 56,
  },
);
</script>

<template>
  <div class="block-skeleton" :style="{ minHeight: `${height}px` }" aria-hidden="true">
    <span class="block-skeleton__bar"></span>
  </div>
</template>

<style scoped lang="scss">
.block-skeleton {
  padding: 8px var(--qsc-cell-pad-x, 16px);
}

.block-skeleton__bar {
  display: block;
  width: 100%;
  height: 100%;
  min-height: 40px;
  border-radius: 10px;
  background: color-mix(in srgb, var(--qsc-text) 6%, transparent);
}
</style>
