<script setup lang="ts">
withDefaults(
  defineProps<{
    title: string;
    hint?: string;
  }>(),
  { hint: "" },
);
</script>

<template>
  <div class="section-head">
    <p class="title">{{ title }}</p>
    <p v-if="hint" class="hint">{{ hint }}</p>
  </div>
</template>
