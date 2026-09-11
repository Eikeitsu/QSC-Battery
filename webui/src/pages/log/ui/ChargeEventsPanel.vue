<script setup lang="ts">
import type { ChargeEvent } from "@/shared/api/events";
import { EVENT_TYPE_LABELS, eventTone } from "../composables/useChargeEvents";

defineProps<{
  events: ChargeEvent[];
  loading: boolean;
  emptyHint?: string;
}>();

defineEmits<{
  refresh: [];
}>();
</script>

<template>
  <div class="events-panel">
    <div class="events-panel__toolbar">
      <span class="muted">{{ loading ? "读取中…" : `共 ${events.length} 条` }}</span>
      <button type="button" class="reload" :disabled="loading" @click="$emit('refresh')">
        刷新
      </button>
    </div>
    <ul v-if="events.length" class="event-list" aria-label="充电事件列表">
      <li v-for="(e, idx) in events" :key="`${e.ts}-${idx}`" class="event-item">
        <div class="event-time">
          <b>{{ e.dateText }}</b>
          <span>{{ e.timeText }}</span>
        </div>
        <div class="event-body">
          <span class="chip" :class="`chip--${eventTone(e.type)}`">
            {{ EVENT_TYPE_LABELS[e.type] || e.type }}
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
      {{ emptyHint || "暂无充电事件。插电、停充或恢复后会自动记录。" }}
    </div>
  </div>
</template>

<style scoped lang="scss">
.events-panel__toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
  font-size: 12px;
}

.reload {
  border: none;
  background: transparent;
  color: var(--qsc-primary);
  font-size: 12px;
  padding: 0;
}

.empty {
  padding: 28px 8px;
  line-height: 1.55;
  text-align: center;
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
  grid-template-columns: 96px 1fr;
  gap: 10px;
  padding: 10px 12px;
  border-radius: 10px;
  background: var(--qsc-surface, #fff);
  border: 1px solid color-mix(in srgb, var(--qsc-text) 6%, transparent);
}

.event-time {
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 11px;
  color: var(--qsc-text-3);
  line-height: 1.25;

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
  border-radius: 6px;
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

.kv b {
  font-weight: 600;
  color: var(--qsc-text);
  margin-left: 2px;
}

.detail {
  color: var(--qsc-text-3);
  flex: 1 1 100%;
}
</style>
