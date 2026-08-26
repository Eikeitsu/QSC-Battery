<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";

const points = ref<api.HistoryPoint[]>([]);
const loading = ref(false);

async function reload() {
  loading.value = true;
  try {
    points.value = await api.loadChargeHistory(288);
  } finally {
    loading.value = false;
  }
}

const levelPath = computed(() => {
  const list = points.value;
  if (list.length < 2) return "";
  const w = 320;
  const h = 88;
  const pad = 6;
  const minT = list[0].ts;
  const maxT = list[list.length - 1].ts || minT + 1;
  const span = Math.max(1, maxT - minT);
  return list
    .map((p, i) => {
      const x = pad + ((p.ts - minT) / span) * (w - pad * 2);
      const y = pad + (1 - Math.min(100, Math.max(0, p.level)) / 100) * (h - pad * 2);
      return `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(" ");
});

const currentPath = computed(() => {
  const list = points.value.filter((p) => p.currentUa != null);
  if (list.length < 2) return "";
  const w = 320;
  const h = 88;
  const pad = 6;
  const minT = points.value[0]?.ts || list[0].ts;
  const maxT = points.value[points.value.length - 1]?.ts || list[list.length - 1].ts;
  const span = Math.max(1, maxT - minT);
  const abs = list.map((p) => Math.abs(p.currentUa || 0));
  const maxA = Math.max(500000, ...abs);
  return list
    .map((p, i) => {
      const x = pad + ((p.ts - minT) / span) * (w - pad * 2);
      const y =
        pad + (1 - Math.min(1, Math.abs(p.currentUa || 0) / maxA)) * (h - pad * 2);
      return `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(" ");
});

const summary = computed(() => {
  const list = points.value;
  if (!list.length) return "暂无采样（开启历史并等待数分钟）";
  const first = list[0];
  const last = list[list.length - 1];
  const hours = Math.max(0.1, (last.ts - first.ts) / 3600);
  return `${list.length} 点 · 约 ${hours.toFixed(1)}h · 电量 ${last.level}%`;
});

onMounted(() => {
  void reload();
});

defineExpose({ reload });
</script>

<template>
  <SectionHead title="充放电曲线" :hint="summary" />
  <ThemedCard>
    <div v-if="!points.length" class="empty">
      {{ loading ? "读取中…" : "尚无历史数据。策略页可开关「充放电历史」。" }}
    </div>
    <div v-else class="chart-wrap">
      <svg
        class="chart"
        viewBox="0 0 320 88"
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        <path v-if="currentPath" class="line current" fill="none" :d="currentPath" />
        <path class="line level" fill="none" :d="levelPath" />
      </svg>
      <div class="legend">
        <span class="lg level">电量 %</span>
        <span class="lg current">电流 |µA|</span>
        <button type="button" class="refresh" :disabled="loading" @click="reload">
          刷新
        </button>
      </div>
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
  height: 96px;
  border-radius: 10px;
  background: var(--qsc-surface-2, color-mix(in srgb, var(--qsc-text) 4%, transparent));
}

.line.level {
  stroke: var(--qsc-primary);
  stroke-width: 2;
  stroke-linecap: round;
  stroke-linejoin: round;
}

.line.current {
  stroke: var(--qsc-warn, #ff976a);
  stroke-width: 1.4;
  stroke-opacity: 0.75;
  stroke-linecap: round;
  stroke-linejoin: round;
}

.legend {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 8px;
  font-size: 11px;
  color: var(--qsc-text-3);
}

.lg.level::before,
.lg.current::before {
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

.lg.current::before {
  background: var(--qsc-warn, #ff976a);
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
