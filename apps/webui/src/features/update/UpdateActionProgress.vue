<script setup lang="ts">
defineProps<{
  label: string;
  progressPct: number;
}>();
</script>

<template>
  <div class="progress" role="status" aria-live="polite">
    <div class="progress-head">
      <span>{{ label }}</span>
      <span class="progress-pct">{{ progressPct }}%</span>
    </div>
    <div class="progress-track">
      <span :style="{ width: `${Math.max(progressPct, 6)}%` }"></span>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use "./update-channel";
</style>
