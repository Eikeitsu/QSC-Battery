<script setup lang="ts">
import { computed, inject } from "vue";
import { BinaryFlag, TabName, ThemePack } from "@/shared";
import { useAppStore, useTheme } from "@/stores";
import { lazyComponent } from "@/shared/lib/lazyComponent";

defineProps<{
  refreshing?: boolean;
}>();
defineEmits<{
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
const DefaultHomeTips = lazyComponent(() => import("./ui/default/HomeTips.vue"));
const HomeChargeChart = lazyComponent(() => import("./ui/HomeChargeChart.vue"));

const theme = useTheme();
const app = useAppStore();
const setTab = inject<(name: TabName) => void>("setTab");

// 采样与显示解耦：采样只决定有没有电流线，这里只看显示开关
const showChart = computed(() => app.settings.chart_show !== BinaryFlag.Off);

function goConfig() {
  setTab?.(TabName.Config);
}
</script>

<template>
  <van-pull-refresh
    :model-value="refreshing"
    :success-duration="0"
    @refresh="$emit('refresh')"
  >
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
        <section class="md3-tonal md3-tips">
          <p><b>过夜</b>：停止 80–90%，恢复间隔 5–10%。</p>
          <p><b>游戏 / 导航</b>：开启温控，高温自动停充。</p>
        </section>
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
      <section class="miuix-card miuix-tips">
        <p>过夜建议停止 80–90%；游戏导航请开温控。</p>
      </section>
    </div>

    <div v-else class="page page-default">
      <DefaultHomeHero />
      <DefaultHomeSwitch />
      <HomeChargeChart v-if="showChart" />
      <DefaultHomeStrategy @open-config="goConfig" />
      <DefaultHomeDetail />
      <DefaultHomeStake />
      <DefaultHomeTips />
    </div>
  </van-pull-refresh>
</template>

<style scoped lang="scss">
.page {
  min-height: calc(100dvh - 56px - var(--qsc-inset-top, 0px) - var(--dock-pad, 72px));
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

.md3-tips {
  padding: 14px 16px;
  font-size: 13px;
  color: var(--qsc-text-2);
  line-height: 1.5;

  p {
    margin: 0 0 6px;

    &:last-child {
      margin-bottom: 0;
    }
  }
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

.miuix-tips {
  margin-top: 12px;
  padding: 12px 14px;
  font-size: 12px;
  color: var(--qsc-text-2);
  line-height: 1.45;

  p {
    margin: 0;
  }
}

.page-miuix :deep(.miuix-card) {
  margin-bottom: 0;
}
</style>
