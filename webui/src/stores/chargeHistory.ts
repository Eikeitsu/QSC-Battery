import { computed, ref } from "vue";
import { defineStore } from "pinia";
import * as api from "@/shared/api";
import type { HistoryPoint } from "@/shared/api/history";

export const SYSTEM_TTL_MS = 5 * 60_000;
export const FAST_TTL_MS = 30_000;
const FETCH_LIMIT = 480;
const DISPLAY_LIMIT = 120;

export type ChargeHistorySource = "sampled" | "system" | "merged";

export function needsSystemHistory(
  samplingEnabled: boolean,
  sampled: HistoryPoint[],
): boolean {
  if (!samplingEnabled) return true;
  return sampled.length < 2;
}

export function applyPoints(
  sampled: HistoryPoint[],
  system: HistoryPoint[],
): { points: HistoryPoint[]; source: ChargeHistorySource } {
  if (sampled.length && system.length) {
    return {
      points: api.mergeHistory(sampled, system).slice(-FETCH_LIMIT),
      source: "merged",
    };
  }
  if (sampled.length) {
    return { points: sampled.slice(-FETCH_LIMIT), source: "sampled" };
  }
  if (system.length) {
    return { points: system.slice(-FETCH_LIMIT), source: "system" };
  }
  return { points: [], source: "system" };
}

export const useChargeHistoryStore = defineStore("chargeHistory", () => {
  const points = ref<HistoryPoint[]>([]);
  const source = ref<ChargeHistorySource>("system");
  const sampledPoints = ref<HistoryPoint[]>([]);
  const systemPoints = ref<HistoryPoint[]>([]);
  const sampledAt = ref(0);
  const systemAt = ref(0);
  const loadingFast = ref(false);
  const loadingSystem = ref(false);
  const active = ref(false);

  let fastGen = 0;
  let systemGen = 0;
  let deferredTimer: ReturnType<typeof setTimeout> | null = null;

  const loading = computed(() => loadingFast.value || loadingSystem.value);

  function syncDisplay() {
    const next = applyPoints(sampledPoints.value, systemPoints.value);
    points.value = next.points;
    source.value = next.source;
  }

  function clearDeferred() {
    if (deferredTimer) clearTimeout(deferredTimer);
    deferredTimer = null;
  }

  function scheduleDeferredSystem(samplingEnabled: boolean) {
    clearDeferred();
    deferredTimer = setTimeout(() => {
      deferredTimer = null;
      if (!active.value) return;
      if (!needsSystemHistory(samplingEnabled, sampledPoints.value)) return;
      if (systemAt.value && Date.now() - systemAt.value < SYSTEM_TTL_MS) return;
      void refreshSystem(false);
    }, 300);
  }

  async function refreshFast(samplingEnabled: boolean, force = false) {
    if (!active.value && !force) return;

    if (!samplingEnabled) {
      sampledPoints.value = [];
      sampledAt.value = Date.now();
      syncDisplay();
      return;
    }

    if (!force && sampledAt.value && Date.now() - sampledAt.value < FAST_TTL_MS) return;

    const gen = ++fastGen;
    loadingFast.value = true;
    try {
      // force=true 时视为用户主动「刷新」：重拉整个最近窗口，避免增量遗漏
      const lastTs =
        !force && sampledPoints.value.length > 0
          ? sampledPoints.value[sampledPoints.value.length - 1]!.ts
          : 0;
      const fresh = lastTs > 0
        ? await api.loadChargeHistorySince(lastTs, DISPLAY_LIMIT)
        : await api.loadChargeHistory(DISPLAY_LIMIT);
      if (gen !== fastGen || !active.value) return;
      if (lastTs > 0 && fresh.length > 0) {
        const merged = [...sampledPoints.value, ...fresh].slice(-FETCH_LIMIT * 2);
        const seen = new Set<number>();
        const dedup: HistoryPoint[] = [];
        for (let i = merged.length - 1; i >= 0; i -= 1) {
          const p = merged[i]!;
          if (seen.has(p.ts)) continue;
          seen.add(p.ts);
          dedup.unshift(p);
        }
        sampledPoints.value = dedup.slice(-FETCH_LIMIT);
      } else {
        sampledPoints.value = fresh;
      }
      sampledAt.value = Date.now();
      syncDisplay();
    } finally {
      if (gen === fastGen) loadingFast.value = false;
    }
  }

  async function refreshSystem(force = false) {
    if (!active.value && !force) return;
    if (!force && systemAt.value && Date.now() - systemAt.value < SYSTEM_TTL_MS) return;

    const gen = ++systemGen;
    loadingSystem.value = true;
    try {
      const system = await api.loadSystemBatteryHistory();
      if (gen !== systemGen || !active.value) return;
      systemPoints.value = system;
      systemAt.value = Date.now();
      syncDisplay();
    } finally {
      if (gen === systemGen) loadingSystem.value = false;
    }
  }

  async function refreshAll(samplingEnabled: boolean) {
    await refreshFast(samplingEnabled, true);
    await refreshSystem(true);
  }

  function activate(samplingEnabled: boolean) {
    active.value = true;
    const fastStale = !sampledAt.value || Date.now() - sampledAt.value >= FAST_TTL_MS;
    if (fastStale || !sampledPoints.value.length) {
      void refreshFast(samplingEnabled).then(() => {
        if (!active.value) return;
        scheduleDeferredSystem(samplingEnabled);
      });
    } else {
      syncDisplay();
      scheduleDeferredSystem(samplingEnabled);
    }
  }

  function onTabActivated(samplingEnabled: boolean) {
    active.value = true;
    void refreshFast(samplingEnabled, false);
    scheduleDeferredSystem(samplingEnabled);
  }

  function deactivate() {
    active.value = false;
    fastGen += 1;
    systemGen += 1;
    clearDeferred();
    loadingFast.value = false;
    loadingSystem.value = false;
  }

  return {
    points,
    source,
    loading,
    loadingFast,
    loadingSystem,
    activate,
    onTabActivated,
    deactivate,
    refreshFast,
    refreshSystem,
    refreshAll,
    scheduleDeferredSystem,
  };
});
