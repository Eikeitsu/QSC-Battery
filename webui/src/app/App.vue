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
  <div v-if="!routerReady" class="app-start-loading" role="status">
    <PageLoading text="正在打开 QSC-Battery…" />
  </div>
  <Suspense v-else timeout="0">
    <RouterView />
    <template #fallback>
      <div class="app-start-loading" role="status">
        <PageLoading text="正在准备页面…" />
      </div>
    </template>
  </Suspense>
</template>

<style scoped>
.app-start-loading {
  min-height: 56px;
  padding-top: var(--qsc-inset-top, 0);
  border-bottom: 1px solid var(--qsc-hairline, rgb(0 0 0 / 8%));
  background: var(--qsc-bg, #eef1f5);
  color: var(--qsc-text, #2d333b);
}

.app-start-loading :deep(.page-loading) {
  justify-content: flex-start;
  min-height: 56px;
  padding: 0 16px;
}

@media (prefers-reduced-motion: reduce) {
  .app-start-loading :deep(.page-loading__spinner) {
    animation-duration: 1.6s;
  }
}
</style>
