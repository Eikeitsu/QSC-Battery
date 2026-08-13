<script setup lang="ts">
import { computed } from "vue";
import { THEME_SWITCH_CLASS, THEME_SWITCH_SIZE } from "@/shared";
import { useTheme } from "@/stores";

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

const packClass = computed(() => THEME_SWITCH_CLASS[theme.themePack]);

/** size 仅作兜底；实际尺寸由 packs/*.scss 控制 */
const size = computed(() => THEME_SWITCH_SIZE[theme.themePack]);
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
  line-height: 0;
}
</style>
