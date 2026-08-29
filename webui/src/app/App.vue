<script setup lang="ts">
import { onMounted, ref } from "vue";
import { RouterView, useRouter } from "vue-router";
import PageLoading from "@/shared/ui/PageLoading.vue";

const router = useRouter();
const routerReady = ref(false);

onMounted(() => {
  void router.isReady().finally(() => {
    routerReady.value = true;
  });
});
</script>

<template>
  <PageLoading v-if="!routerReady" text="正在打开 QSC-Battery…" />
  <Suspense v-else timeout="0">
    <RouterView />
    <template #fallback>
      <PageLoading text="正在打开页面…" />
    </template>
  </Suspense>
</template>
