<script setup lang="ts">
import { useAppStore } from "@/stores";

defineEmits<{
  refresh: [];
  clear: [];
}>();

const store = useAppStore();
</script>

<template>
  <section class="md3-tonal log-md3-meta">
    <div class="log-md3-meta__row">
      <div>
        <div class="log-md3-meta__title">运行日志</div>
        <div class="log-md3-meta__sub">
          最近 {{ store.logLines }} 行 · {{ store.logSize }}
        </div>
      </div>
      <div class="log-md3-meta__actions">
        <van-button size="small" round type="primary" @click="$emit('refresh')">
          刷新
        </van-button>
        <van-button size="small" round plain type="danger" @click="$emit('clear')">
          清空
        </van-button>
      </div>
    </div>
  </section>
  <section class="md3-tonal log-md3-body">
    <pre class="log">{{ store.logText }}</pre>
  </section>
</template>

<style scoped lang="scss">
.log {
  margin: 0;
  white-space: pre-wrap;
  word-break: break-all;
  font-size: 12px;
  line-height: 1.55;
  color: var(--qsc-text);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  min-height: 42vh;
}

.log-md3-meta {
  padding: 16px 18px;
  margin-bottom: 12px;
}

.log-md3-meta__row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.log-md3-meta__title {
  font-size: 17px;
  font-weight: 600;
}

.log-md3-meta__sub {
  margin-top: 4px;
  font-size: 12px;
  color: var(--qsc-text-2);
}

.log-md3-meta__actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

.log-md3-body {
  padding: 14px 16px;
}
</style>
