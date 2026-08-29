<script setup lang="ts">
import { RouterView } from "vue-router";
import PageLoading from "@/shared/ui/PageLoading.vue";
</script>

<template>
  <Suspense timeout="0">
    <RouterView />
    <template #fallback>
      <PageLoading text="正在打开 QSC-Battery…" />
    </template>
  </Suspense>
</template>
