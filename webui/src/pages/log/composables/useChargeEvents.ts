import { computed, onMounted, ref } from "vue";
import type { ChargeEvent, ChargeEventType } from "@/shared/api/events";
import { loadChargeEvents } from "@/shared/api/events";

export const EVENT_TYPE_LABELS: Record<ChargeEventType, string> = {
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

export function eventTone(t: ChargeEventType): string {
  switch (t) {
    case "CHARGE_STOP":
      return "warn";
    case "CHARGE_START":
      return "ok";
    case "UNPLUG":
      return "muted";
    case "WARNING":
    case "THERMAL":
      return "danger";
    default:
      return "soft";
  }
}

export function useChargeEvents(maxLines = 80) {
  const events = ref<ChargeEvent[]>([]);
  const loadingEvents = ref(false);

  const eventSummary = computed(() => {
    if (!events.value.length) return "尚无事件";
    const last = events.value[events.value.length - 1]!;
    const t = EVENT_TYPE_LABELS[last.type] || last.type;
    return `${events.value.length} 条 · 最近 ${last.timeText} ${t}${
      last.level != null ? ` ${last.level}%` : ""
    }`;
  });

  const eventsNewestFirst = computed(() => events.value.slice().reverse());

  async function refreshEvents() {
    loadingEvents.value = true;
    try {
      events.value = await loadChargeEvents(maxLines);
    } finally {
      loadingEvents.value = false;
    }
  }

  onMounted(() => {
    void refreshEvents();
  });

  return {
    events,
    eventsNewestFirst,
    loadingEvents,
    eventSummary,
    refreshEvents,
  };
}
