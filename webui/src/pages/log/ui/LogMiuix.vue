<script setup lang="ts">
import { useAppStore } from "@/stores";

defineEmits<{
  refresh: [];
  clear: [];
}>();

const store = useAppStore();
</script>

<template>
  <div class="miuix-label">日志</div>
  <section class="miuix-card log-miuix-meta">
    <div class="miuix-pref-static">
      <span>最近行数</span>
      <b>{{ store.logLines }}</b>
    </div>
    <div class="miuix-pref-static">
      <span>文件大小</span>
      <b>{{ store.logSize }}</b>
    </div>
    <div class="miuix-actions">
      <button type="button" class="miuix-btn" @click="$emit('refresh')">刷新</button>
      <button type="button" class="miuix-btn danger" @click="$emit('clear')">清空</button>
    </div>
  </section>
  <div class="miuix-label">内容</div>
  <section class="miuix-card log-miuix-body">
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

.miuix-label {
  margin: 12px 10px 8px;
  font-size: 13px;
  font-weight: 600;
  color: var(--qsc-text-2);
}

.log-miuix-meta {
  margin-bottom: 0;
}

.miuix-pref-static {
  display: flex;
  justify-content: space-between;
  padding: 13px 14px;
  font-size: 15px;
  border-bottom: 1px solid var(--qsc-hairline);

  b {
    font-weight: 550;
    color: var(--qsc-text-2);
  }
}

.miuix-actions {
  display: flex;
  gap: 10px;
  padding: 12px 14px;
}

.miuix-btn {
  flex: 1;
  border: none;
  border-radius: 10px;
  padding: 10px 12px;
  font-size: 14px;
  font-weight: 550;
  background: var(--qsc-surface-2);
  color: var(--qsc-text);

  &.danger {
    color: var(--qsc-danger);
  }

  &:active {
    opacity: 0.85;
  }
}

.log-miuix-body {
  padding: 12px;
}
</style>
