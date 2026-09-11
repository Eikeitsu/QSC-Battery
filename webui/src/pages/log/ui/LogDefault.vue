<script setup lang="ts">
import type { ChargeEvent } from "@/shared/api/events";
import type { LogEntry, LogSession } from "@/shared";
import { useAppStore } from "@/stores";
import type { LogPageTab } from "../composables/useLogPage";
import ChargeEventsPanel from "./ChargeEventsPanel.vue";
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
  logTab: LogPageTab;
  events: ChargeEvent[];
  loadingEvents: boolean;
  eventSummary: string;
}>();

defineEmits<{
  refresh: [];
  clear: [];
  "refresh-events": [];
  "update:levelFilter": [v: string];
  "update:viewMode": [v: "flat" | "session"];
  "update:logTab": [v: LogPageTab];
}>();

const store = useAppStore();
</script>

<template>
  <div class="tabs" role="tablist" aria-label="日志视图">
    <button
      type="button"
      role="tab"
      class="tab"
      :class="{ active: logTab === 'runtime' }"
      :aria-selected="logTab === 'runtime'"
      @click="$emit('update:logTab', 'runtime')"
    >
      运行日志
    </button>
    <button
      type="button"
      role="tab"
      class="tab"
      :class="{ active: logTab === 'events' }"
      :aria-selected="logTab === 'events'"
      @click="$emit('update:logTab', 'events')"
    >
      充电事件
    </button>
  </div>

  <template v-if="logTab === 'runtime'">
    <section class="card meta">
      <div class="row">
        <div class="row-text">
          <span class="row-title">运行日志</span>
          <span class="row-sub">最近 {{ store.logLines }} 行 · {{ store.logSize }}</span>
        </div>
        <div class="actions">
          <van-button size="small" type="primary" plain @click="$emit('refresh')">
            刷新
          </van-button>
          <van-button size="small" type="danger" plain @click="$emit('clear')">
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
    <section class="card log-card" :class="{ session: viewMode === 'session' }">
      <LogSessions
        v-if="viewMode === 'session'"
        :sessions="sessions"
        :filtered="filterActive"
      />
      <LogLines v-else :lines="lines" :filtered="filterActive" />
    </section>
  </template>

  <template v-else>
    <section class="card meta">
      <div class="row">
        <div class="row-text">
          <span class="row-title">充电事件</span>
          <span class="row-sub">{{ eventSummary }}</span>
        </div>
        <div class="actions">
          <van-button size="small" type="primary" plain @click="$emit('refresh-events')">
            刷新
          </van-button>
          <van-button size="small" type="danger" plain @click="$emit('clear')">
            清空
          </van-button>
        </div>
      </div>
      <p class="hint">记录插拔、停充、恢复与异常节点，便于回顾充电过程。</p>
    </section>
    <section class="card events">
      <ChargeEventsPanel :events="events" :loading="loadingEvents" />
    </section>
  </template>
</template>

<style scoped lang="scss">
.tabs {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px;
  padding: 4px;
  margin: 0 0 12px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--qsc-text) 6%, transparent);
}

.tab {
  appearance: none;
  border: none;
  border-radius: 9px;
  padding: 10px 8px;
  font-size: 13px;
  font-weight: 550;
  color: var(--qsc-text-2);
  background: transparent;
  transition:
    background 0.15s ease,
    color 0.15s ease,
    box-shadow 0.15s ease;

  &.active {
    color: var(--qsc-text);
    background: var(--qsc-surface, #fff);
    box-shadow: 0 1px 3px color-mix(in srgb, var(--qsc-text) 12%, transparent);
  }
}

.meta {
  padding: 14px var(--qsc-cell-pad-x, 16px) 12px;
  margin-bottom: 12px;
}

.row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 10px;
}

.row-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.row-title {
  font-size: 14px;
  font-weight: 650;
  color: var(--qsc-text);
}

.row-sub {
  font-size: 12px;
  color: var(--qsc-text-3);
}

.actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

.toolbar {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 10px;
  margin-top: 2px;
}

.toolbar-label {
  font-size: 12px;
  color: var(--qsc-text-3);
  white-space: nowrap;
}

.hint {
  margin: 10px 0 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text-3);
}

.log-card,
.events {
  padding: 12px var(--qsc-cell-pad-x, 16px) 14px;
  background: var(--qsc-surface-2);
}

.log-card.session {
  background: transparent;
  border: none;
  box-shadow: none;
}
</style>
