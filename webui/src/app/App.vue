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
  <div v-if="!routerReady" class="app-start-loading">
    <PageLoading text="正在打开 QSC-Battery…" />
  </div>
  <Suspense v-else timeout="0">
    <RouterView />
    <template #fallback>
      <PageLoading text="正在打开页面…" />
    </template>
  </Suspense>
</template>

<style scoped>
.app-start-loading {
  min-height: 100dvh;
  display: grid;
  place-items: center;
  background: var(--qsc-bg, #eef1f5);
}

.app-start-loading :deep(.page-loading) {
  min-width: 156px;
  padding: 20px 24px;
  border: 1px solid color-mix(in srgb, var(--qsc-primary, #596574) 16%, transparent);
  border-radius: 18px;
  background: var(--qsc-surface, #fff);
  box-shadow: var(--qsc-shadow, 0 12px 36px rgb(15 18 22 / 10%));
}
</style>
