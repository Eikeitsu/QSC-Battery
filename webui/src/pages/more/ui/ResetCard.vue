<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { useAboutActions } from "../composables/useAboutActions";

const { resetConfig } = useAboutActions();
</script>

<template>
  <SectionHead title="配置" />
  <ThemedCard>
    <van-cell
      title="恢复默认配置"
      label="电量 / 温控 / 电流控制恢复初始值"
      is-link
      @click="resetConfig"
    />
  </ThemedCard>
</template>
