<script setup lang="ts">
import ThemeSwitch from "./ThemeSwitch.vue";

withDefaults(
  defineProps<{
    title: string;
    label?: string;
    modelValue?: boolean;
  }>(),
  {
    label: "",
    modelValue: false,
  },
);

defineEmits<{
  "update:modelValue": [v: boolean];
}>();
</script>

<template>
  <van-cell center :title="title" :label="label || undefined">
    <template #right-icon>
      <ThemeSwitch
        :model-value="modelValue"
        @update:model-value="$emit('update:modelValue', $event)"
      />
    </template>
  </van-cell>
</template>
