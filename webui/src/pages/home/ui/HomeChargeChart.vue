<script setup lang="ts">
import { computed, onActivated, onDeactivated, onMounted, onUnmounted, ref, watch } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { BinaryFlag } from "@/shared";
import { useAppStore, useChargeHistoryStore } from "@/stores";
import { STORAGE_KEYS, readStorage, writeStorage } from "@/shared/config/storage";
import { downsampleByTime, buildSmoothPath } from "@/shared/lib/chartPath";
import type { HistoryPoint } from "@/shared/api/history";
import * as api from "@/shared/api/history";

const app = useAppStore();
const history = useChargeHistoryStore();

/** 采样关闭后模块不再写入充电段，曲线只剩系统电池记录（无电流线） */
const samplingEnabled = computed(() => app.settings.history_enable !== BinaryFlag.Off);

const W = 320;
const H = 96;
const PAD_L = 26;
const PAD_R = 30;
const PAD_T = 8;
const PAD_B = 16;

const RANGE_OPTIONS = [
  { label: "3h", seconds: 3 * 3600 },
  { label: "12h", seconds: 12 * 3600 },
  { label: "24h", seconds: 24 * 3600 },
  { label: "全部", seconds: 0 },
];

const rangeSec = ref(Math.max(0, Number(readStorage(STORAGE_KEYS.chargeRange)) || 0));
watch(rangeSec, (v) => writeStorage(STORAGE_KEYS.chargeRange, String(v)));

const healthPoints = ref<api.HealthPoint[]>([]);
(async () => {
  healthPoints.value = await api.loadHealthHistory();
})();

let refreshTimer: ReturnType<typeof setInterval> | null = null;
let chartActive = false;
const chartNow = ref(Math.floor(Date.now() / 1000));

function trimByRange<T extends { ts: number }>(points: T[], maxAgeSec: number): T[] {
  if (maxAgeSec <= 0) return points;
  const cutoff = chartNow.value - maxAgeSec;
  let lo = 0;
  let hi = points.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (points[mid]!.ts < cutoff) lo = mid + 1;
    else hi = mid;
  }
  return points.slice(lo);
}

const timeScopedPoints = computed(() => trimByRange(history.points, rangeSec.value));

const displayPoints = computed(() => downsampleByTime(timeScopedPoints.value, 120));

const timeSpan = computed(() => {
  const list = displayPoints.value;
  if (list.length < 2) {
    // 即使没数据也按所选范围画一个空坐标轴，帮助用户理解「该范围内无曲线」
    if (rangeSec.value > 0) {
      const maxT = chartNow.value;
      return { minT: maxT - rangeSec.value, maxT, span: rangeSec.value };
    }
    return null;
  }
  const minT = Math.min(list[0]!.ts, rangeSec.value > 0 ? chartNow.value - rangeSec.value : list[0]!.ts);
  const maxT = Math.max(list[list.length - 1]!.ts, rangeSec.value > 0 ? chartNow.value : list[list.length - 1]!.ts);
  return { minT, maxT, span: Math.max(1, maxT - minT) };
});

function xAt(ts: number) {
  const t = timeSpan.value;
  if (!t) return PAD_L;
  return PAD_L + ((ts - t.minT) / t.span) * (W - PAD_L - PAD_R);
}

function yAt(ratio: number) {
  const clamped = Math.min(1, Math.max(0, ratio));
  return PAD_T + (1 - clamped) * (H - PAD_T - PAD_B);
}

function smoothPath(list: HistoryPoint[], ratio: (p: HistoryPoint) => number) {
  return buildSmoothPath(
    list,
    (p) => xAt(p.ts),
    (p) => yAt(ratio(p)),
  );
}

const levelPath = computed(() =>
  displayPoints.value.length < 2
    ? ""
    : smoothPath(displayPoints.value, (p) => p.level / 100),
);

const tempPath = computed(() => {
  const list = displayPoints.value.filter((p) => p.temp != null);
  return list.length < 2 ? "" : smoothPath(list, (p) => (p.temp as number) / 100);
});

const currentScale = computed(() => {
  const abs = displayPoints.value
    .filter((p) => p.currentUa != null)
    .map((p) => Math.abs(p.currentUa as number));
  if (!abs.length) return 0;
  const peak = Math.max(...abs);
  return Math.max(500_000, Math.ceil(peak / 500_000) * 500_000);
});

const currentPath = computed(() => {
  const list = displayPoints.value.filter((p) => p.currentUa != null);
  const max = currentScale.value;
  if (list.length < 2 || !max) return "";
  return smoothPath(list, (p) => Math.abs(p.currentUa as number) / max);
});

const yTicks = computed(() =>
  [0, 50, 100].map((v) => ({
    v,
    y: yAt(v / 100),
    right: currentScale.value
      ? `${((currentScale.value * (v / 100)) / 1_000_000).toFixed(1)}`
      : "",
  })),
);

const xTicks = computed(() => {
  const t = timeSpan.value;
  if (!t) return [];
  return [0, 0.5, 1].map((f) => {
    const ts = t.minT + t.span * f;
    const d = new Date(ts * 1000);
    const hh = String(d.getHours()).padStart(2, "0");
    const mm = String(d.getMinutes()).padStart(2, "0");
    return {
      x: xAt(ts),
      label: `${hh}:${mm}`,
      anchor: f === 0 ? "start" : f === 1 ? "end" : "middle",
    };
  });
});

const axisNote = computed(() => {
  const base = currentPath.value
    ? "左轴：电量 % / 温度 °C · 右轴：电流绝对值 A"
    : "左轴：电量 % / 温度 °C";
  if (!samplingEnabled.value) {
    return `${base}。已关闭「充放电历史」采样：曲线来自系统电池记录，没有充电电流线。`;
  }
  if (history.source === "merged") return `${base}。模块采样与系统记录已合并；电流仅在模块采样点显示。点「刷新」可重新补齐放电段。`;
  if (history.source === "sampled") return `${base}。当前为模块采样数据（含充电电流）。点「刷新」可补齐系统放电段。`;
  return `${base}。当前仅有系统电池历史，暂时没有模块电流采样点。`;
});

const healthNote = computed(() => {
  const list = healthPoints.value;
  if (!list.length) return "";
  const last = list[list.length - 1]!;
  const soh = last.soh != null ? `SOH ${last.soh}%` : "";
  const cc = last.cycleCount != null ? `循环 ${last.cycleCount} 次` : "";
  return [soh, cc].filter(Boolean).join(" · ");
});

const summary = computed(() => {
  const list = timeScopedPoints.value;
  if (!list.length) {
    if (history.loadingFast || history.loadingSystem) return "正在读取…";
    return samplingEnabled.value ? "暂无数据" : "仅系统记录";
  }
  const first = list[0]!;
  const last = list[list.length - 1]!;
  const seconds = Math.max(0, last.ts - first.ts);
  const duration =
    seconds >= 3600 ? `${(seconds / 3600).toFixed(1)}h` : `${Math.floor(seconds / 60)}m`;
  const currentLevel = /^\d+$/.test(app.status.level)
    ? app.status.level
    : String(last.level);
  const currentTemp = /^\d+$/.test(app.status.temp)
    ? ` · ${app.status.temp}°C`
    : last.temp != null
      ? ` · ${last.temp}°C`
      : "";
  const sourceLabel =
    history.source === "merged"
      ? "系统+模块合并"
      : history.source === "sampled"
        ? "模块采样"
        : "系统历史";
  return `${list.length} 点 · ${duration} · 当前 ${currentLevel}%${currentTemp} · ${sourceLabel}`;
});

function refreshAll() {
  void history.refreshAll(samplingEnabled.value);
  void (async () => {
    healthPoints.value = await api.loadHealthHistory();
  })();
}

function startFastTimer() {
  refreshTimer = setInterval(() => {
    chartNow.value = Math.floor(Date.now() / 1000);
    void history.refreshFast(samplingEnabled.value, false);
  }, 30_000);
}

onMounted(() => {
  chartActive = true;
  history.activate(samplingEnabled.value);
  startFastTimer();
});

onActivated(() => {
  if (chartActive) return;
  chartActive = true;
  history.onTabActivated(samplingEnabled.value);
  startFastTimer();
});

onDeactivated(() => {
  chartActive = false;
  history.deactivate();
  if (refreshTimer) clearInterval(refreshTimer);
  refreshTimer = null;
});

onUnmounted(() => {
  history.deactivate();
  if (refreshTimer) clearInterval(refreshTimer);
  refreshTimer = null;
});

defineExpose({ reload: refreshAll });
</script>

<template>
  <SectionHead title="充放电曲线" :hint="summary" />
  <ThemedCard>
    <div class="range-bar" role="tablist" aria-label="曲线时间范围">
      <button
        v-for="opt in RANGE_OPTIONS"
        :key="opt.label"
        type="button"
        class="range-chip"
        :class="{ active: rangeSec === opt.seconds }"
        @click="rangeSec = opt.seconds"
      >
        {{ opt.label }}
      </button>
    </div>
    <div v-if="!history.points.length" class="empty">
      <div v-if="history.loading" class="chart-skeleton" role="status" aria-live="polite">
        <span class="chart-skeleton__bar" aria-hidden="true"></span>
        <span class="chart-skeleton__text">正在读取曲线数据…</span>
      </div>
      <template v-else>
        尚无历史数据。系统电池记录可能刚被清空，用一段时间后即有曲线。
      </template>
    </div>
    <div v-else class="chart-wrap">
      <svg class="chart" :viewBox="`0 0 ${W} ${H}`" role="img" aria-label="充放电曲线">
        <g class="grid">
          <line
            v-for="t in yTicks"
            :key="`g${t.v}`"
            :x1="PAD_L"
            :x2="W - PAD_R"
            :y1="t.y"
            :y2="t.y"
          />
        </g>
        <g class="axis-text">
          <text
            v-for="t in yTicks"
            :key="`l${t.v}`"
            :x="PAD_L - 4"
            :y="t.y + 3"
            text-anchor="end"
          >
            {{ t.v }}
          </text>
          <text
            v-for="t in yTicks"
            :key="`r${t.v}`"
            :x="W - PAD_R + 4"
            :y="t.y + 3"
            text-anchor="start"
          >
            {{ t.right }}
          </text>
          <text
            v-for="t in xTicks"
            :key="`x${t.label}`"
            :x="t.x"
            :y="H - 4"
            :text-anchor="t.anchor"
          >
            {{ t.label }}
          </text>
        </g>
        <path v-if="currentPath" class="line current" fill="none" :d="currentPath" />
        <path v-if="tempPath" class="line temp" fill="none" :d="tempPath" />
        <path class="line level" fill="none" :d="levelPath" />
      </svg>
      <div class="legend">
        <span class="lg level">电量 %</span>
        <span class="lg temp">温度 °C</span>
        <span v-if="currentPath" class="lg current">电流 A</span>
        <button
          type="button"
          class="refresh"
          :disabled="history.loading"
          @click="refreshAll"
        >
          {{ history.loadingSystem ? "补齐中…" : "刷新" }}
        </button>
      </div>
      <p class="axis-note">
        {{ axisNote }}
        <template v-if="healthNote">
          <br />
          电池健康：{{ healthNote }}
        </template>
      </p>
    </div>
  </ThemedCard>
</template>

<style scoped lang="scss">
.range-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  padding: 10px var(--qsc-cell-pad-x, 16px) 0;
}

.range-chip {
  border: 1px solid color-mix(in srgb, var(--qsc-text) 12%, transparent);
  background: transparent;
  color: var(--qsc-text-2);
  font-size: 12px;
  border-radius: 999px;
  padding: 4px 10px;
  line-height: 1.2;

  &.active {
    border-color: var(--qsc-primary);
    color: var(--qsc-primary);
    background: color-mix(in srgb, var(--qsc-primary) 10%, transparent);
  }
}

.empty {
  padding: 16px var(--qsc-cell-pad-x, 16px);
  font-size: 13px;
  color: var(--qsc-text-3);
  line-height: 1.45;
}

.chart-skeleton {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 48px;
}

.chart-skeleton__bar {
  width: 100%;
  height: 72px;
  border-radius: 10px;
  background: linear-gradient(
    90deg,
    color-mix(in srgb, var(--qsc-text) 6%, transparent) 0%,
    color-mix(in srgb, var(--qsc-text) 12%, transparent) 50%,
    color-mix(in srgb, var(--qsc-text) 6%, transparent) 100%
  );
  background-size: 200% 100%;
  animation: chart-skeleton-shimmer 1.2s ease-in-out infinite;
}

.chart-skeleton__text {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
}

@keyframes chart-skeleton-shimmer {
  from {
    background-position: 100% 0;
  }

  to {
    background-position: -100% 0;
  }
}

.chart-wrap {
  padding: 10px var(--qsc-cell-pad-x, 16px) 12px;
}

.chart {
  display: block;
  width: 100%;
  height: 132px;
  border-radius: 10px;
  background: var(--qsc-surface-2, color-mix(in srgb, var(--qsc-text) 4%, transparent));
}

.grid line {
  stroke: var(--qsc-text-3);
  stroke-opacity: 0.25;
  stroke-width: 0.6;
  stroke-dasharray: 3 3;
}

.axis-text text {
  fill: var(--qsc-text-3);
  font-size: 7px;
}

.line {
  stroke-linecap: round;
  stroke-linejoin: round;
}

.line.level {
  stroke: var(--qsc-primary);
  stroke-width: 1.8;
}

.line.temp {
  stroke: var(--qsc-danger, #ee5a52);
  stroke-width: 1.3;
  stroke-opacity: 0.85;
}

.line.current {
  stroke: var(--qsc-warn, #ff976a);
  stroke-width: 1.2;
  stroke-opacity: 0.7;
}

.legend {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 8px;
  font-size: 11px;
  color: var(--qsc-text-3);
}

.lg::before {
  content: "";
  display: inline-block;
  width: 10px;
  height: 2px;
  margin-right: 4px;
  vertical-align: middle;
  border-radius: 1px;
}

.lg.level::before {
  background: var(--qsc-primary);
}

.lg.temp::before {
  background: var(--qsc-danger, #ee5a52);
}

.lg.current::before {
  background: var(--qsc-warn, #ff976a);
}

.axis-note {
  margin: 6px 0 0;
  font-size: 11px;
  color: var(--qsc-text-3);
  line-height: 1.4;
}

.refresh {
  margin-left: auto;
  border: none;
  background: transparent;
  color: var(--qsc-primary);
  font-size: 12px;
  padding: 4px 0;
}
</style>
