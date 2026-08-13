<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import { useAppStore } from "@/stores";

defineEmits<{
  refresh: [];
  clear: [];
}>();

const store = useAppStore();
</script>

<template>
  <SectionHead title="运行日志" hint="模块触发停充 / 恢复时写入" />
  <section class="card meta">
    <div class="row">
      <span>最近 {{ store.logLines }} 行</span>
      <span>{{ store.logSize }}</span>
    </div>
    <div class="actions">
      <van-button size="small" type="primary" plain @click="$emit('refresh')">
        刷新
      </van-button>
      <van-button size="small" type="danger" plain @click="$emit('clear')">
        清空
      </van-button>
    </div>
  </section>
  <section class="card log-card">
    <pre class="log">{{ store.logText }}</pre>
  </section>
</template>

<style scoped lang="scss">
.meta {
  padding: 14px 16px;
  margin-bottom: 12px;
}

.row {
  display: flex;
  justify-content: space-between;
  font-size: 13px;
  color: var(--qsc-text-2);
  margin-bottom: 12px;
}

.actions {
  display: flex;
  gap: 8px;
}

.log-card {
  padding: 14px;
  background: var(--qsc-surface-2);
}

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
</style>
