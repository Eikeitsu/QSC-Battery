<script setup lang="ts">
import { computed, inject, ref } from "vue";
import { BinaryFlag, TabName, ThemePack } from "@/shared";
import { useAppStore, useTheme } from "@/stores";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const props = defineProps<{
  refreshing?: boolean;
}>();
const emit = defineEmits<{
  refresh: [];
}>();

const Md3HomeStatus = lazyComponent(() => import("./ui/md3/HomeStatus.vue"));
const Md3HomeMetrics = lazyComponent(() => import("./ui/md3/HomeMetrics.vue"));
const Md3HomeStrategy = lazyComponent(() => import("./ui/md3/HomeStrategy.vue"));
const Md3HomeBattery = lazyComponent(() => import("./ui/md3/HomeBattery.vue"));
const Md3HomeInfo = lazyComponent(() => import("./ui/md3/HomeInfo.vue"));
const MiuixHomeOverview = lazyComponent(() => import("./ui/miuix/HomeOverview.vue"));
const MiuixHomeStrategy = lazyComponent(() => import("./ui/miuix/HomeStrategy.vue"));
const MiuixHomeDetail = lazyComponent(() => import("./ui/miuix/HomeDetail.vue"));
const MiuixHomeBattery = lazyComponent(() => import("./ui/miuix/HomeBattery.vue"));
const DefaultHomeHero = lazyComponent(() => import("./ui/default/HomeHero.vue"));
const DefaultHomeSwitch = lazyComponent(() => import("./ui/default/HomeSwitch.vue"));
const DefaultHomeStrategy = lazyComponent(() => import("./ui/default/HomeStrategy.vue"));
const DefaultHomeDetail = lazyComponent(() => import("./ui/default/HomeDetail.vue"));
const DefaultHomeStake = lazyComponent(() => import("./ui/default/HomeStake.vue"));
const HomeTips = lazyComponent(() => import("./ui/HomeTips.vue"));
const HomeChargeChart = lazyComponent(() => import("./ui/HomeChargeChart.vue"));

const theme = useTheme();
const app = useAppStore();
const setTab = inject<(name: TabName) => void>("setTab");

// 采样与显示解耦：采样只决定有没有电流线，这里只看显示开关
const showChart = computed(() => app.settings.chart_show !== BinaryFlag.Off);
const pullDistance = ref(0);
const touchStart = ref<{ x: number; y: number } | null>(null);
const PULL_THRESHOLD = 64;

function isAtScrollTop() {
  return (document.querySelector<HTMLElement>(".app-main")?.scrollTop ?? 0) <= 0;
}

function isInteractiveTarget(target: EventTarget | null) {
  return (
    target instanceof Element &&
    Boolean(
      target.closest(
        "button, a, input, textarea, select, .van-switch, .van-cell, .van-field, [role='button'], [role='switch']",
      ),
    )
  );
}

function onTouchStart(event: TouchEvent) {
  if (!isAtScrollTop() || isInteractiveTarget(event.target)) {
    touchStart.value = null;
    return;
  }
  const touch = event.touches[0];
  touchStart.value = touch ? { x: touch.clientX, y: touch.clientY } : null;
  pullDistance.value = 0;
}

function onTouchMove(event: TouchEvent) {
  const start = touchStart.value;
  const touch = event.touches[0];
  if (!start || !touch || !isAtScrollTop()) return;
  const dx = touch.clientX - start.x;
  const dy = touch.clientY - start.y;
  if (dy <= 0 || dy <= Math.abs(dx)) return;
  pullDistance.value = Math.min(dy, 96);
  if (pullDistance.value >= PULL_THRESHOLD && event.cancelable) {
    event.preventDefault();
  }
}

function finishPull() {
  if (pullDistance.value >= PULL_THRESHOLD && !props.refreshing) {
    emit("refresh");
  }
  touchStart.value = null;
  pullDistance.value = 0;
}

function goConfig() {
  setTab?.(TabName.Config);
}
</script>

<template>
  <div
    class="home-refresh"
    :class="{
      'home-refresh--pulling': pullDistance > 0,
      'home-refresh--loading': refreshing,
    }"
    :style="{ '--qsc-pull-distance': `${pullDistance}px` }"
    @touchstart.passive="onTouchStart"
    @touchmove="onTouchMove"
    @touchend="finishPull"
    @touchcancel="finishPull"
  >
    <div class="home-refresh__indicator" role="status" aria-live="polite">
      <span class="home-refresh__spinner" aria-hidden="true"></span>
      <span>{{ refreshing ? "正在刷新…" : "下拉刷新" }}</span>
    </div>
    <div class="home-refresh__body">
      <div v-if="theme.themePack === ThemePack.Md3" class="page page-md3">
      <div class="md3-stack">
        <Md3HomeStatus />
        <Md3HomeMetrics />
        <HomeChargeChart v-if="showChart" />
        <Md3HomeStrategy @open-config="goConfig" />
        <div class="md3-label">电池健康</div>
        <Md3HomeBattery />
        <div class="md3-label">运行详情</div>
        <Md3HomeInfo />
        <HomeTips variant="md3" />
      </div>
    </div>

    <div v-else-if="theme.themePack === ThemePack.Miuix" class="page page-miuix">
      <div class="miuix-label">总览</div>
      <MiuixHomeOverview />
      <template v-if="showChart">
        <div class="miuix-label">曲线</div>
        <HomeChargeChart />
      </template>
      <div class="miuix-label">当前策略</div>
      <MiuixHomeStrategy @open-config="goConfig" />
      <div class="miuix-label">更多</div>
      <MiuixHomeDetail />
      <div class="miuix-label">电池</div>
      <MiuixHomeBattery />
      <HomeTips variant="miuix" />
    </div>

    <div v-else class="page page-default">
      <DefaultHomeHero />
      <DefaultHomeSwitch />
      <HomeChargeChart v-if="showChart" />
      <DefaultHomeStrategy @open-config="goConfig" />
      <DefaultHomeDetail />
      <DefaultHomeStake />
      <HomeTips />
    </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
.page {
  min-height: calc(100dvh - 56px - var(--qsc-inset-top, 0px) - var(--dock-pad, 72px));
}

.home-refresh {
  position: relative;
  touch-action: pan-y;
}

.home-refresh__body {
  transform: translateY(
    var(--qsc-pull-offset, var(--qsc-pull-distance, 0px))
  );
  transition: transform 160ms ease;
  will-change: transform;
}

.home-refresh--pulling .home-refresh__body {
  transition: none;
}

.home-refresh--loading {
  --qsc-pull-offset: 36px;
}

.home-refresh__indicator {
  position: sticky;
  top: 0;
  z-index: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 28px;
  margin-bottom: -28px;
  gap: 6px;
  color: var(--qsc-text-3);
  font-size: 12px;
  opacity: 0;
  pointer-events: none;
  transform: translateY(calc(var(--qsc-pull-distance, 0px) - 28px));
  transition: opacity 120ms ease;
}

.home-refresh--pulling .home-refresh__indicator,
.home-refresh--loading .home-refresh__indicator {
  opacity: 1;
}

.home-refresh__spinner {
  width: 15px;
  height: 15px;
  border: 2px solid color-mix(in srgb, var(--qsc-primary) 22%, transparent);
  border-top-color: var(--qsc-primary);
  border-radius: 50%;
}

.home-refresh--loading .home-refresh__spinner {
  animation: home-refresh-spin 0.8s linear infinite;
}

@keyframes home-refresh-spin {
  to {
    transform: rotate(360deg);
  }
}

.md3-stack {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.md3-label {
  margin: 4px 4px 0;
  font-size: 13px;
  font-weight: 600;
  color: var(--qsc-text-2);
}

.miuix-label {
  margin: 14px 10px 8px;
  font-size: 13px;
  font-weight: 600;
  color: var(--qsc-text-2);

  &:first-child {
    margin-top: 4px;
  }
}

.page-miuix :deep(.miuix-card) {
  margin-bottom: 0;
}
</style>
