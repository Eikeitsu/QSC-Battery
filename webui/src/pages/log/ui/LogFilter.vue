<script setup lang="ts">
import ChipGroup from "@/shared/ui/ChipGroup.vue";
import { LOG_LEVEL_PRESETS } from "@/shared";

defineProps<{
  modelValue: string;
}>();

defineEmits<{
  "update:modelValue": [id: string];
}>();
</script>

<template>
  <ChipGroup
    :options="LOG_LEVEL_PRESETS"
    :model-value="modelValue"
    @update:model-value="$emit('update:modelValue', String($event))"
  />
</template>
