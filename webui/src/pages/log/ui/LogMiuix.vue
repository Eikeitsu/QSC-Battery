<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import type { ChargeEvent, ChargeEventType } from "@/shared/api/events";
import { loadChargeEvents } from "@/shared/api/events";
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
const events = ref<ChargeEvent[]>([]);
const loadingEvents = ref(false);

const eventTypeLabels: Record<ChargeEventType, string> = {
  PLUG: "插电",
  UNPLUG: "拔线",
  CHARGE_START: "开始充电",
  CHARGE_STOP: "停充",
  MAINTAIN: "维持",
  HEALTH: "健康",
  THERMAL: "温度",
  WARNING: "警告",
  CUSTOM: "自定义",
};

const eventSummary = computed(() => {
  if (!events.value.length) return "0 条";
  const last = events.value[events.value.length - 1]!;
  const t = eventTypeLabels[last.type] || last.type;
  return `${events.value.length} 条 · 最近 ${last.timeText} ${t}`;
});

async function refreshEvents() {
  loadingEvents.value = true;
  try {
    events.value = await loadChargeEvents(80);
  } finally {
    loadingEvents.value = false;
  }
}

onMounted(() => {
  void refreshEvents();
});

defineExpose({ refreshEvents });
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

  <div class="miuix-label">充电事件 · {{ eventSummary }}</div>
  <section class="miuix-card events-miuix">
    <div class="events-miuix__head">
      <span class="tip">
        {{ loadingEvents ? "读取中…" : "模块在插拔 / 停充 / 温度节点写入，最近 80 条" }}
      </span>
      <button type="button" class="miuix-btn mini" @click="refreshEvents">刷新</button>
    </div>
    <template v-if="events.length">
      <div
        v-for="(e, idx) in events.slice().reverse()"
        :key="`${e.ts}-${idx}`"
        class="event-row"
      >
        <div class="time-col">
          <span class="d">{{ e.dateText }}</span>
          <span class="t">{{ e.timeText }}</span>
        </div>
        <div class="info-col">
          <div class="line1">
            <span class="tag">{{ eventTypeLabels[e.type] || e.type }}</span>
            <span v-if="e.level != null" class="stat">电量 {{ e.level }}%</span>
            <span v-if="e.temp != null" class="stat">温度 {{ e.temp }}°C</span>
          </div>
          <div v-if="e.detail" class="line2">{{ e.detail }}</div>
        </div>
      </div>
    </template>
    <div v-else class="empty-row">暂无充电事件记录</div>
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

  &.mini {
    flex: 0 0 auto;
    padding: 6px 10px;
    font-size: 12px;
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

.events-miuix__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 12px 14px;
  border-bottom: 1px solid var(--qsc-hairline);
  font-size: 12px;
  color: var(--qsc-text-3);
}

.event-row {
  display: grid;
  grid-template-columns: 106px 1fr;
  gap: 12px;
  padding: 12px 14px;
  border-bottom: 1px solid var(--qsc-hairline);

  &:last-child {
    border-bottom: none;
  }
}

.empty-row {
  padding: 22px 14px;
  text-align: center;
  color: var(--qsc-text-3);
  font-size: 13px;
}

.time-col {
  display: flex;
  flex-direction: column;
  gap: 2px;
  color: var(--qsc-text-3);
  font-size: 11px;
  line-height: 1.25;

  .d {
    font-weight: 600;
    color: var(--qsc-text-2);
  }
}

.info-col {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}

.line1 {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: var(--qsc-text);
}

.tag {
  display: inline-flex;
  align-items: center;
  height: 22px;
  padding: 0 8px;
  border-radius: 6px;
  background: var(--qsc-surface-2);
  font-size: 11px;
  font-weight: 600;
  color: var(--qsc-primary);
}

.stat {
  color: var(--qsc-text-2);
}

.line2 {
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.45;
  word-break: break-word;
}
</style>
