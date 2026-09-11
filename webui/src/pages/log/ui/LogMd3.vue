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
  <div class="md3-tabs" role="tablist" aria-label="日志视图">
    <button
      type="button"
      role="tab"
      class="md3-tab"
      :class="{ active: logTab === 'runtime' }"
      :aria-selected="logTab === 'runtime'"
      @click="$emit('update:logTab', 'runtime')"
    >
      运行日志
    </button>
    <button
      type="button"
      role="tab"
      class="md3-tab"
      :class="{ active: logTab === 'events' }"
      :aria-selected="logTab === 'events'"
      @click="$emit('update:logTab', 'events')"
    >
      充电事件
    </button>
  </div>

  <template v-if="logTab === 'runtime'">
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

  <template v-else>
    <section class="md3-tonal log-md3-meta">
      <div class="log-md3-meta__row">
        <div>
          <div class="log-md3-meta__title">充电事件</div>
          <div class="log-md3-meta__sub">{{ eventSummary }}</div>
        </div>
        <div class="log-md3-meta__actions">
          <van-button size="small" round type="primary" @click="$emit('refresh-events')">
            刷新
          </van-button>
          <van-button size="small" round plain type="danger" @click="$emit('clear')">
            清空
          </van-button>
        </div>
      </div>
    </section>
    <section class="md3-tonal events-md3">
      <ChargeEventsPanel
        :events="events"
        :loading="loadingEvents"
      />
    </section>
  </template>
</template>

<style scoped lang="scss">
.md3-tabs {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 6px;
  padding: 5px;
  margin-bottom: 14px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--qsc-primary) 10%, transparent);
}

.md3-tab {
  appearance: none;
  border: none;
  border-radius: 999px;
  padding: 10px 12px;
  font-size: 13px;
  font-weight: 600;
  color: var(--qsc-text-2);
  background: transparent;

  &.active {
    color: #fff;
    background: var(--qsc-primary);
  }
}

.log-md3-meta {
  padding: 18px var(--qsc-cell-pad-x, 20px) 14px;
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
  margin-top: 2px;
  font-size: 12px;
  color: var(--qsc-text-3);
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

.log-md3-body,
.events-md3 {
  padding: 14px var(--qsc-cell-pad-x, 20px) 16px;
  min-height: 180px;
}

.log-md3-body.session {
  background: transparent;
  box-shadow: none;
}
</style>
