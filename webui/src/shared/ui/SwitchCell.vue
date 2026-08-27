<script setup lang="ts">
import ThemeSwitch from "./ThemeSwitch.vue";

withDefaults(
  defineProps<{
    title: string;
    label?: string;
    modelValue?: boolean;
    disabled?: boolean;
  }>(),
  {
    label: "",
    modelValue: false,
    disabled: false,
  },
);

defineEmits<{
  "update:modelValue": [v: boolean];
}>();
</script>

<template>
  <van-cell
    center
    :title="title"
    :label="label || undefined"
    :class="{ 'switch-cell-disabled': disabled }"
  >
    <template #right-icon>
      <ThemeSwitch
        :model-value="modelValue"
        :disabled="disabled"
        @update:model-value="$emit('update:modelValue', $event)"
      />
    </template>
  </van-cell>
</template>

<style scoped lang="scss">
.switch-cell-disabled :deep(.van-cell__title) {
  opacity: 0.5;
}
</style>
