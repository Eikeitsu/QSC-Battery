<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
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

function eventChipClass(t: ChargeEventType) {
  switch (t) {
    case "CHARGE_STOP":
      return "chip chip--warn";
    case "CHARGE_START":
      return "chip chip--ok";
    case "UNPLUG":
      return "chip chip--muted";
    case "WARNING":
    case "THERMAL":
      return "chip chip--danger";
    default:
      return "chip chip--soft";
  }
}

const eventSummary = computed(() => {
  if (!events.value.length) return "（尚无事件）";
  const last = events.value[events.value.length - 1]!;
  const t = eventTypeLabels[last.type] || last.type;
  return `${events.value.length} 条 · 最近一次 ${last.timeText} ${t}${last.level != null ? ` ${last.level}%` : ""}`;
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
  <SectionHead title="运行日志" hint="模块触发停充 / 恢复时写入" />
  <section class="card meta">
    <div class="row">
      <span>最近 {{ store.logLines }} 行 · {{ store.logSize }}</span>
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

  <SectionHead title="充电事件" :hint="eventSummary" />
  <section class="card events">
    <div class="events-toolbar">
      <span class="muted" v-if="loadingEvents">读取中…</span>
      <button
        type="button"
        class="reload"
        :disabled="loadingEvents"
        @click="refreshEvents"
      >
        刷新
      </button>
    </div>
    <ul v-if="events.length" class="event-list" aria-label="充电事件列表">
      <li
        v-for="(e, idx) in events.slice().reverse()"
        :key="`${e.ts}-${idx}`"
        class="event-item"
      >
        <div class="event-time">
          <b>{{ e.dateText }}</b>
          <span>{{ e.timeText }}</span>
        </div>
        <div class="event-body">
          <span :class="eventChipClass(e.type)">
            {{ eventTypeLabels[e.type] || e.type }}
          </span>
          <span v-if="e.level != null" class="kv">
            电量 <b>{{ e.level }}%</b>
          </span>
          <span v-if="e.temp != null" class="kv">
            温度 <b>{{ e.temp }}°C</b>
          </span>
          <span v-if="e.detail" class="detail">{{ e.detail }}</span>
        </div>
      </li>
    </ul>
    <div v-else class="empty muted">
      暂无充电事件。触发插电 / 停充后，模块会写入插拔、停充维持与温度节点等记录。
    </div>
  </section>
</template>

<style scoped lang="scss">
.meta {
  padding: 14px var(--qsc-cell-pad-x, 16px);
  margin-bottom: 12px;
}

.row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: var(--qsc-text-2);
  margin-bottom: 4px;
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
  margin-top: 4px;
}

.toolbar-label {
  font-size: 12px;
  color: var(--qsc-text-3);
  white-space: nowrap;
}

.log-card {
  padding: 14px;
  background: var(--qsc-surface-2);
}

.log-card.session {
  padding: 10px;
  background: transparent;
  border: none;
  box-shadow: none;
}

.events {
  margin-top: 12px;
  padding: 12px var(--qsc-cell-pad-x, 16px) 14px;
  background: var(--qsc-surface-2);
}

.events-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
  font-size: 12px;
}

.reload {
  border: none;
  background: transparent;
  color: var(--qsc-primary);
  font-size: 12px;
}

.empty {
  padding: 16px 4px;
  line-height: 1.5;
}

.muted {
  color: var(--qsc-text-3);
}

.event-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.event-item {
  display: grid;
  grid-template-columns: 108px 1fr;
  gap: 10px;
  padding: 10px 12px;
  border-radius: 10px;
  background: var(--qsc-surface, #fff);
}

.event-time {
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 11px;
  color: var(--qsc-text-3);
  line-height: 1.2;

  b {
    font-weight: 550;
    color: var(--qsc-text-2);
  }
}

.event-body {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: var(--qsc-text-2);
}

.chip {
  display: inline-flex;
  align-items: center;
  height: 22px;
  padding: 0 8px;
  border-radius: 999px;
  font-size: 11px;
  line-height: 22px;
  font-weight: 550;

  &--soft {
    background: color-mix(in srgb, var(--qsc-primary) 12%, transparent);
    color: var(--qsc-primary);
  }

  &--ok {
    background: color-mix(in srgb, var(--qsc-success, #1db954) 14%, transparent);
    color: var(--qsc-success, #1db954);
  }

  &--warn {
    background: color-mix(in srgb, var(--qsc-warn, #ff976a) 14%, transparent);
    color: var(--qsc-warn, #cc6d2b);
  }

  &--danger {
    background: color-mix(in srgb, var(--qsc-danger, #ee5a52) 14%, transparent);
    color: var(--qsc-danger, #b3322b);
  }

  &--muted {
    background: color-mix(in srgb, var(--qsc-text) 8%, transparent);
    color: var(--qsc-text-2);
  }
}

.kv {
  b {
    font-weight: 600;
    color: var(--qsc-text);
    margin-left: 2px;
  }
}

.detail {
  color: var(--qsc-text-3);
  flex: 1 1 100%;
}
</style>
