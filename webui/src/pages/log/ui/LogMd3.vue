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
    <LogFilter
      :model-value="levelFilter"
      @update:model-value="$emit('update:levelFilter', $event)"
    />
    <div class="toolbar">
      <span class="toolbar-label">内容视图</span>
      <LogViewToggle
        :model-value="viewMode"
        @update:model-value="$emit('update:viewMode', $event)"
      />
    </div>
  </section>
  <section class="md3-tonal log-md3-body" :class="{ session: viewMode === 'session' }">
    <LogSessions
      v-if="viewMode === 'session'"
      :sessions="sessions"
      :filtered="filterActive"
    />
    <LogLines v-else :lines="lines" :filtered="filterActive" />
  </section>
</template>

<style scoped lang="scss">
.log-md3-meta {
  padding: 16px 18px 12px;
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

.toolbar {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 10px;
  margin-top: 10px;
}

.toolbar-label {
  font-size: 12px;
  color: var(--qsc-text-3);
  white-space: nowrap;
}

.log-md3-body {
  padding: 14px 16px;
}

.log-md3-body.session {
  padding: 8px;
  background: transparent;
}
</style>
