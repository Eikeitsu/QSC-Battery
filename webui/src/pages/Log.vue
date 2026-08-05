<script setup lang="ts">
import { showConfirmDialog } from "vant";
import { useAppStore } from "../stores";

defineProps<{
  refreshing?: boolean;
}>();
defineEmits<{
  refresh: [];
}>();

const store = useAppStore();

async function onClear() {
  try {
    await showConfirmDialog({
      title: "清空日志",
      message: "确认清空运行日志？",
    });
    await store.clearLog();
  } catch {
    /* cancelled */
  }
}
</script>

<template>
  <van-pull-refresh
    :model-value="refreshing"
    success-text="日志已刷新"
    @refresh="$emit('refresh')"
  >
    <div class="page">
      <div class="section-head">
        <p class="title">运行日志</p>
        <p class="hint">模块触发停充 / 恢复时写入</p>
      </div>
      <section class="card meta">
        <div class="row">
          <span>最近 {{ store.logLines }} 行</span>
          <span>{{ store.logSize }}</span>
        </div>
        <div class="actions">
          <van-button size="small" type="primary" plain @click="$emit('refresh')">
            刷新
          </van-button>
          <van-button size="small" type="danger" plain @click="onClear">
            清空
          </van-button>
        </div>
      </section>
      <section class="card log-card">
        <pre class="log">{{ store.logText }}</pre>
      </section>
    </div>
  </van-pull-refresh>
</template>

<style scoped lang="scss">
.page {
  min-height: calc(100vh - 120px);
}

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
