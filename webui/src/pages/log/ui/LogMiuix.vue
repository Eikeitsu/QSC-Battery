<script setup lang="ts">
import type { LogEntry, LogSession } from "@/shared";
import { useAppStore } from "@/stores";
import LogFilter from "./LogFilter.vue";
import LogLines from "./LogLines.vue";
import LogSessions from "./LogSessions.vue";
import LogViewToggle from "./LogViewToggle.vue";

defineProps<{
  lines: LogEntry[];
  sessions: LogSession[];
  viewMode: "flat" | "session";
  levelFilter: string;
  filterActive: boolean;
}>();

defineEmits<{
  refresh: [];
  clear: [];
  "update:levelFilter": [v: string];
  "update:viewMode": [v: "flat" | "session"];
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
    <div class="miuix-filter">
      <LogFilter
        :model-value="levelFilter"
        @update:model-value="$emit('update:levelFilter', $event)"
      />
    </div>
    <div class="miuix-view">
      <span class="miuix-view__label">内容视图</span>
      <LogViewToggle
        :model-value="viewMode"
        @update:model-value="$emit('update:viewMode', $event)"
      />
    </div>
    <div class="miuix-actions">
      <button type="button" class="miuix-btn" @click="$emit('refresh')">刷新</button>
      <button type="button" class="miuix-btn danger" @click="$emit('clear')">清空</button>
    </div>
  </section>
  <div class="miuix-label">{{ viewMode === "session" ? "会话" : "内容" }}</div>
  <section class="miuix-card log-miuix-body" :class="{ session: viewMode === 'session' }">
    <LogSessions
      v-if="viewMode === 'session'"
      :sessions="sessions"
      :filtered="filterActive"
    />
    <LogLines v-else :lines="lines" :filtered="filterActive" />
  </section>
</template>

<style scoped lang="scss">
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
  align-items: center;
  padding: 13px 14px;
  font-size: 15px;
  border-bottom: 1px solid var(--qsc-hairline);

  b {
    font-weight: 550;
    color: var(--qsc-text-2);
  }
}

.miuix-filter {
  padding: 10px 14px 8px;
  border-bottom: 1px solid var(--qsc-hairline);
}

.miuix-view {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 12px;
  padding: 10px 14px;
  border-bottom: 1px solid var(--qsc-hairline);
}

.miuix-view__label {
  font-size: 15px;
  color: var(--qsc-text);
  white-space: nowrap;
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

.log-miuix-body.session {
  padding: 8px;
  background: transparent;
}
</style>
