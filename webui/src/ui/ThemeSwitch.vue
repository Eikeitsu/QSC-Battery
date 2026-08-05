<script setup lang="ts">
import { computed } from "vue";
import { useTheme } from "../stores";

const props = withDefaults(
  defineProps<{
    modelValue?: boolean;
    disabled?: boolean;
  }>(),
  {
    modelValue: false,
    disabled: false,
  },
);

defineEmits<{
  "update:modelValue": [v: boolean];
}>();

const theme = useTheme();

const packClass = computed(() => {
  if (theme.themePack === "md3") return "ts-md3";
  if (theme.themePack === "miuix") return "ts-miuix";
  return "ts-default";
});

const size = computed(() => {
  if (theme.themePack === "md3") return "28px";
  if (theme.themePack === "miuix") return "30px";
  return "22px";
});
</script>

<template>
  <span class="theme-switch" :class="packClass">
    <van-switch
      :model-value="props.modelValue"
      :disabled="props.disabled"
      :size="size"
      @update:model-value="(v) => $emit('update:modelValue', !!v)"
    />
  </span>
</template>

<style scoped lang="scss">
.theme-switch {
  display: inline-flex;
  align-items: center;
  flex-shrink: 0;
}
</style>
