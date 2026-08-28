<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";
import { BinaryFlag } from "@/shared";
import { useAppStore } from "@/stores";

const app = useAppStore();
const points = ref<api.HistoryPoint[]>([]);
const loading = ref(false);

/** 采样关闭后模块不再写入充电段，曲线只剩系统电池记录（无电流线） */
const samplingOff = computed(() => app.settings.history_enable === BinaryFlag.Off);

const W = 320;
const H = 96;
const PAD_L = 26;
const PAD_R = 30;
const PAD_T = 8;
const PAD_B = 16;

const sysCount = ref(0);
let refreshTimer: ReturnType<typeof setInterval> | null = null;

async function reload() {
  loading.value = true;
  try {
    // 充电段来自模块采样（有电流线），放电段读系统 batterystats 历史（零额外采样）。
    // 采样关闭时旧文件已过期，只用系统记录。
    const [sampled, system] = await Promise.all([
      samplingOff.value
        ? Promise.resolve<api.HistoryPoint[]>([])
        : api.loadChargeHistory(288),
      api.loadSystemBatteryHistory(),
    ]);
    const merged = api.mergeHistory(sampled, system);
    const visible = merged.slice(-480);
    const sampledTimes = new Set(sampled.map((point) => point.ts));
    sysCount.value = visible.filter((point) => !sampledTimes.has(point.ts)).length;
    points.value = visible;
  } finally {
    loading.value = false;
  }
}

const timeSpan = computed(() => {
  const list = points.value;
  if (list.length < 2) return null;
  const minT = list[0].ts;
  const maxT = list[list.length - 1].ts;
  return { minT, span: Math.max(1, maxT - minT) };
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

function buildPath(list: api.HistoryPoint[], ratio: (p: api.HistoryPoint) => number) {
  return list
    .map(
      (p, i) =>
        `${i === 0 ? "M" : "L"}${xAt(p.ts).toFixed(1)} ${yAt(ratio(p)).toFixed(1)}`,
    )
    .join(" ");
}

const levelPath = computed(() =>
  points.value.length < 2 ? "" : buildPath(points.value, (p) => p.level / 100),
);

/** 温度与电量共用左轴 0–100 的比例位置（°C 直接映射，多数机型 20–60） */
const tempPath = computed(() => {
  const list = points.value.filter((p) => p.temp != null);
  return list.length < 2 ? "" : buildPath(list, (p) => (p.temp as number) / 100);
});

const currentScale = computed(() => {
  const abs = points.value
    .filter((p) => p.currentUa != null)
    .map((p) => Math.abs(p.currentUa as number));
  if (!abs.length) return 0;
  // 取整到 0.5A，右轴刻度好读
  const peak = Math.max(...abs);
  return Math.max(500_000, Math.ceil(peak / 500_000) * 500_000);
});

const currentPath = computed(() => {
  const list = points.value.filter((p) => p.currentUa != null);
  const max = currentScale.value;
  if (list.length < 2 || !max) return "";
  return buildPath(list, (p) => Math.abs(p.currentUa as number) / max);
});

/** 左轴：电量 % / 温度 °C 共用；右轴：电流 A */
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

const axisNote = computed(() =>
  currentPath.value
    ? "左轴：电量 % / 温度 °C · 右轴：电流绝对值 A"
    : "左轴：电量 % / 温度 °C",
);

const summary = computed(() => {
  const list = points.value;
  if (!list.length) return samplingOff.value ? "仅系统记录" : "暂无数据";
  const first = list[0];
  const last = list[list.length - 1];
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
  const sys = sysCount.value > 0 ? ` · 含系统记录 ${sysCount.value} 点` : "";
  return `${list.length} 点 · ${duration} · 当前 ${currentLevel}%${currentTemp}${sys}`;
});

onMounted(() => {
  void reload();
  refreshTimer = setInterval(() => {
    void reload();
  }, 30_000);
});

watch(
  () => [app.status.updatedAt, app.settings.history_enable] as const,
  ([updatedAt, historyEnable], previous) => {
    if (
      updatedAt !== "--" &&
      (updatedAt !== previous?.[0] || historyEnable !== previous?.[1])
    ) {
      void reload();
    }
  },
);

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer);
});

defineExpose({ reload });
</script>

<template>
  <SectionHead title="充放电曲线" :hint="summary" />
  <ThemedCard>
    <div v-if="!points.length" class="empty">
      {{
        loading
          ? "读取中…"
          : "尚无历史数据。系统电池记录可能刚被清空，用一段时间后即有曲线。"
      }}
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
        <button type="button" class="refresh" :disabled="loading" @click="reload">
          刷新
        </button>
      </div>
      <p class="axis-note">
        {{ axisNote }}
        <br />
        <template v-if="samplingOff">
          已关闭「充放电历史」采样：曲线全部来自系统电池记录，没有充电电流线。
        </template>
        <template v-else>
          电流线仅充电段有：放电段直接读系统电池记录，不额外采样。
        </template>
      </p>
    </div>
  </ThemedCard>
</template>

<style scoped lang="scss">
.empty {
  padding: 16px var(--qsc-cell-pad-x, 16px);
  font-size: 13px;
  color: var(--qsc-text-3);
  line-height: 1.45;
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
