<script setup lang="ts">
import { computed } from "vue";
import { THEME_CARD_CLASS } from "@/shared";
import { useTheme } from "@/stores";

const props = withDefaults(
  defineProps<{
    tag?: string;
    extraClass?: string;
  }>(),
  {
    tag: "section",
    extraClass: "",
  },
);

const theme = useTheme();

const cardClass = computed(() => [
  "card",
  THEME_CARD_CLASS[theme.themePack],
  props.extraClass,
]);
</script>

<template>
  <component :is="tag" :class="cardClass">
    <slot></slot>
  </component>
</template>
