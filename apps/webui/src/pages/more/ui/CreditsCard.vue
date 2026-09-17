<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { CREDITS } from "@/shared";
import { useAboutActions } from "../composables/useAboutActions";

const { open } = useAboutActions();
</script>

<template>
  <SectionHead title="致谢" />
  <ThemedCard>
    <van-cell
      v-for="item in CREDITS"
      :key="item.url"
      :title="item.name"
      :label="item.role"
      is-link
      @click="open(item.url)"
    />
  </ThemedCard>
</template>
