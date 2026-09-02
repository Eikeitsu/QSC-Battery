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

function eventTone(t: ChargeEventType) {
  switch (t) {
    case "CHARGE_STOP":
      return "warn";
    case "CHARGE_START":
      return "success";
    case "UNPLUG":
      return "muted";
    case "WARNING":
    case "THERMAL":
      return "danger";
    default:
      return "primary";
  }
}

const eventSummary = computed(() => {
  if (!events.value.length) return "尚无事件";
  const last = events.value[events.value.length - 1]!;
  const t = eventTypeLabels[last.type] || last.type;
  return `${events.value.length} 条 · 最近一次 ${last.timeText} ${t}`;
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

  <div class="md3-gap"></div>
  <section class="md3-tonal events-md3">
    <div class="events-md3__head">
      <div>
        <div class="title">充电事件</div>
        <div class="sub">{{ eventSummary }}</div>
      </div>
      <button
        type="button"
        class="fbtn"
        :disabled="loadingEvents"
        @click="refreshEvents"
      >
        {{ loadingEvents ? "读取中" : "刷新" }}
      </button>
    </div>
    <ul v-if="events.length" class="event-list">
      <li
        v-for="(e, idx) in events.slice().reverse()"
        :key="`${e.ts}-${idx}`"
        class="event-item"
      >
        <div class="time">
          <span class="d">{{ e.dateText }}</span>
          <span class="t">{{ e.timeText }}</span>
        </div>
        <div class="content">
          <div class="row-a">
            <span class="pill" :class="`pill--${eventTone(e.type)}`">
              {{ eventTypeLabels[e.type] || e.type }}
            </span>
            <span v-if="e.level != null" class="meta">
              电量 <b>{{ e.level }}%</b>
            </span>
            <span v-if="e.temp != null" class="meta">
              温度 <b>{{ e.temp }}°C</b>
            </span>
          </div>
          <p v-if="e.detail" class="detail">{{ e.detail }}</p>
        </div>
      </li>
    </ul>
    <div v-else class="empty">
      暂无充电事件。模块会在插电、停充维持、过温等节点写入记录。
    </div>
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

.md3-gap {
  height: 12px;
}

.events-md3 {
  padding: 16px 18px;
  border-radius: 20px;
}

.events-md3__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}

.title {
  font-size: 18px;
  font-weight: 600;
}

.sub {
  margin-top: 4px;
  font-size: 12px;
  color: var(--qsc-text-2);
}

.fbtn {
  border: none;
  border-radius: 999px;
  padding: 8px 14px;
  font-size: 12px;
  font-weight: 550;
  background: color-mix(in srgb, var(--qsc-primary) 16%, transparent);
  color: var(--qsc-primary);
}

.event-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.event-item {
  display: grid;
  grid-template-columns: 110px 1fr;
  gap: 14px;
  padding: 14px 14px;
  border-radius: 16px;
  background: color-mix(in srgb, var(--qsc-surface) 92%, var(--qsc-primary) 8%);
}

.time {
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 11px;
  color: var(--qsc-text-3);
  line-height: 1.2;

  .d {
    font-weight: 600;
    color: var(--qsc-text-2);
  }
}

.content {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}

.row-a {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: var(--qsc-text-2);
}

.pill {
  display: inline-flex;
  align-items: center;
  height: 24px;
  padding: 0 10px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;

  &--primary {
    background: color-mix(in srgb, var(--qsc-primary) 20%, transparent);
    color: var(--qsc-primary);
  }

  &--success {
    background: color-mix(in srgb, var(--qsc-success, #1db954) 22%, transparent);
    color: var(--qsc-success, #1db954);
  }

  &--warn {
    background: color-mix(in srgb, var(--qsc-warn, #ff976a) 24%, transparent);
    color: var(--qsc-warn, #cc6d2b);
  }

  &--danger {
    background: color-mix(in srgb, var(--qsc-danger, #ee5a52) 22%, transparent);
    color: var(--qsc-danger, #c23a32);
  }

  &--muted {
    background: color-mix(in srgb, var(--qsc-text) 10%, transparent);
    color: var(--qsc-text-2);
  }
}

.meta b {
  font-weight: 600;
  color: var(--qsc-text);
  margin-left: 2px;
}

.detail {
  margin: 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text-3);
}

.empty {
  padding: 18px 4px;
  font-size: 13px;
  color: var(--qsc-text-3);
  line-height: 1.5;
}
</style>
