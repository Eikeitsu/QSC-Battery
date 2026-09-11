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
  <div class="miuix-seg" role="tablist" aria-label="日志视图">
    <button
      type="button"
      role="tab"
      class="seg-item"
      :class="{ active: logTab === 'runtime' }"
      :aria-selected="logTab === 'runtime'"
      @click="$emit('update:logTab', 'runtime')"
    >
      运行日志
    </button>
    <button
      type="button"
      role="tab"
      class="seg-item"
      :class="{ active: logTab === 'events' }"
      :aria-selected="logTab === 'events'"
      @click="$emit('update:logTab', 'events')"
    >
      充电事件
    </button>
  </div>

  <template v-if="logTab === 'runtime'">
    <div class="miuix-label">运行日志</div>
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
        <button type="button" class="miuix-btn danger" @click="$emit('clear')">
          清空
        </button>
      </div>
    </section>

    <div class="miuix-label">{{ viewMode === "session" ? "会话" : "内容" }}</div>
    <section
      class="miuix-card log-miuix-body"
      :class="{ session: viewMode === 'session' }"
    >
      <LogSessions
        v-if="viewMode === 'session'"
        :sessions="sessions"
        :filtered="filterActive"
      />
      <LogLines v-else :lines="lines" :filtered="filterActive" />
    </section>
  </template>

  <template v-else>
    <div class="miuix-label">充电事件 · {{ eventSummary }}</div>
    <section class="miuix-card events-miuix">
      <div class="miuix-actions top">
        <button type="button" class="miuix-btn" @click="$emit('refresh-events')">
          刷新
        </button>
        <button type="button" class="miuix-btn danger" @click="$emit('clear')">
          清空
        </button>
      </div>
      <div class="events-miuix__body">
        <ChargeEventsPanel
          :events="events"
          :loading="loadingEvents"
          empty-hint="暂无充电事件记录"
        />
      </div>
    </section>
  </template>
</template>

<style scoped lang="scss">
.miuix-seg {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0;
  margin: 4px 0 2px;
  border-radius: 10px;
  overflow: hidden;
  background: color-mix(in srgb, var(--qsc-text) 7%, transparent);
}

.seg-item {
  appearance: none;
  border: none;
  padding: 11px 8px;
  font-size: 14px;
  font-weight: 550;
  color: var(--qsc-text-2);
  background: transparent;

  &.active {
    color: var(--qsc-text);
    background: var(--qsc-surface, #fff);
  }
}

.miuix-label {
  margin: 14px 4px 8px;
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
  padding: 13px var(--qsc-cell-pad-x, 16px);
  font-size: 15px;
  border-bottom: 1px solid var(--qsc-hairline);

  b {
    font-weight: 550;
    color: var(--qsc-text-2);
  }
}

.miuix-filter {
  padding: 10px var(--qsc-cell-pad-x, 16px) 8px;
  border-bottom: 1px solid var(--qsc-hairline);
}

.miuix-view {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 12px;
  padding: 10px var(--qsc-cell-pad-x, 16px);
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
  padding: 12px var(--qsc-cell-pad-x, 16px);

  &.top {
    border-bottom: 1px solid var(--qsc-hairline);
  }
}

.miuix-btn {
  flex: 1;
  height: 36px;
  border: none;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 550;
  color: var(--qsc-primary);
  background: color-mix(in srgb, var(--qsc-primary) 12%, transparent);

  &.danger {
    color: var(--qsc-danger, #ee5a52);
    background: color-mix(in srgb, var(--qsc-danger, #ee5a52) 10%, transparent);
  }
}

.log-miuix-body {
  padding: 12px var(--qsc-cell-pad-x, 16px) 14px;
  min-height: 160px;

  &.session {
    background: transparent;
    box-shadow: none;
  }
}

.events-miuix__body {
  padding: 12px var(--qsc-cell-pad-x, 16px) 14px;
}
</style>
