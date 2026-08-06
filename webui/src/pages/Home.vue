<script setup lang="ts">
import { inject } from "vue";
import ThemeSwitch from "../ui/ThemeSwitch.vue";
import { useAppStore, useTheme } from "../stores";
import type { TabName } from "../shared/types";
import Md3HomeStatus from "../skins/md3/HomeStatus.vue";
import Md3HomeMetrics from "../skins/md3/HomeMetrics.vue";
import Md3HomeStrategy from "../skins/md3/HomeStrategy.vue";
import Md3HomeInfo from "../skins/md3/HomeInfo.vue";
import MiuixHomeOverview from "../skins/miuix/HomeOverview.vue";
import MiuixHomeStrategy from "../skins/miuix/HomeStrategy.vue";
import MiuixHomeDetail from "../skins/miuix/HomeDetail.vue";

defineProps<{
  refreshing?: boolean;
}>();
defineEmits<{
  refresh: [];
}>();

const store = useAppStore();
const theme = useTheme();
const setTab = inject<(name: TabName) => void>("setTab");

function goConfig() {
  setTab?.("config");
}

function badgeType(t: string): "primary" | "success" | "warning" | "danger" {
  if (t === "success" || t === "warning" || t === "danger" || t === "primary") {
    return t;
  }
  return "primary";
}
</script>

<template>
  <van-pull-refresh
    :model-value="refreshing"
    :success-duration="0"
    @refresh="$emit('refresh')"
  >
    <!-- MD3：tonal 状态 + 并排指标 + List 策略 -->
    <div v-if="theme.themePack === 'md3'" class="page page-md3">
      <div class="md3-stack">
        <Md3HomeStatus />
        <Md3HomeMetrics />
        <Md3HomeStrategy @open-config="goConfig" />
        <div class="md3-label">运行详情</div>
        <Md3HomeInfo />
        <section class="md3-tonal md3-tips">
          <p><b>过夜</b>：停止 80–90%，恢复间隔 5–10%。</p>
          <p><b>游戏 / 导航</b>：开启温控，高温自动停充。</p>
        </section>
      </div>
    </div>

    <!-- MIUIX：单卡总览 + 设置行策略 -->
    <div v-else-if="theme.themePack === 'miuix'" class="page page-miuix">
      <div class="miuix-label">总览</div>
      <MiuixHomeOverview />
      <div class="miuix-label">当前策略</div>
      <MiuixHomeStrategy @open-config="goConfig" />
      <div class="miuix-label">更多</div>
      <MiuixHomeDetail />
      <section class="miuix-card miuix-tips">
        <p>过夜建议停止 80–90%；游戏导航请开温控。</p>
      </section>
    </div>

    <!-- 默认：现有布局 -->
    <div v-else class="page page-default">
      <section class="hero card">
        <div class="hero-glow"></div>
        <div class="metrics">
          <div class="metric">
            <div class="value">{{ store.status.level }}</div>
            <div class="label">电量 %</div>
          </div>
          <div class="divider"></div>
          <div class="metric">
            <div class="value">{{ store.status.temp }}</div>
            <div class="label">温度 °C</div>
          </div>
        </div>
        <div class="status-row">
          <van-tag round :type="badgeType(store.status.badgeType)">
            {{ store.status.badge }}
          </van-tag>
          <span class="updated">{{ store.status.updatedAt }}</span>
        </div>
        <p class="desc">{{ store.status.desc }}</p>
      </section>

      <section class="card switch-card">
        <van-cell center title="模块总开关" label="关闭后不再自动停充 / 恢复">
          <template #right-icon>
            <ThemeSwitch
              :model-value="store.status.moduleOn"
              @update:model-value="store.toggleModule"
            />
          </template>
        </van-cell>
      </section>

      <div class="section-head">
        <p class="title">当前策略</p>
        <p class="hint">点按可前往策略页调整</p>
      </div>
      <section class="card strategy" @click="goConfig">
        <div class="strategy-row">
          <span class="k">电量停充</span>
          <span class="v">{{ store.powerPlan }}</span>
        </div>
        <div class="strategy-row">
          <span class="k">温控停充</span>
          <span class="v">{{ store.tempPlan }}</span>
        </div>
        <div class="strategy-row">
          <span class="k">充满再停</span>
          <span class="v">{{ store.fullPlan }}</span>
        </div>
        <div class="strategy-row">
          <span class="k">兼容模式</span>
          <span class="v">{{ store.compatPlan }}</span>
        </div>
        <div v-if="store.currentFeature" class="strategy-row">
          <span class="k">电流控制</span>
          <span class="v">{{ store.currentPlan }}</span>
        </div>
        <div class="go">前往策略 →</div>
      </section>

      <div class="section-head">
        <p class="title">运行详情</p>
      </div>
      <section class="card">
        <div class="mini-grid">
          <div class="mini">
            <div class="mv">{{ store.status.chargeLabel }}</div>
            <div class="ml">充电状态</div>
          </div>
          <div class="mini">
            <div class="mv">{{ store.status.voltage }}</div>
            <div class="ml">电压 V</div>
          </div>
          <div class="mini">
            <div class="mv">{{ store.status.currentMa }}</div>
            <div class="ml">电流 mA</div>
          </div>
          <div class="mini">
            <div class="mv">{{ store.status.version }}</div>
            <div class="ml">版本</div>
          </div>
        </div>
      </section>

      <section class="tips card">
        <p><b>过夜</b>：停止 80–90%，恢复间隔 5–10%。</p>
        <p><b>游戏 / 导航</b>：开启温控，高温自动停充。</p>
      </section>
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

.page-default {
  .hero {
    position: relative;
    overflow: hidden;
  }

  .metrics {
    margin-bottom: 12px;
  }

  .divider {
    width: 1px;
    margin: 8px 12px;
    background: color-mix(in srgb, var(--qsc-hairline) 90%, transparent);
  }

  .status-row {
    margin-bottom: 10px;
  }

  .updated {
    font-size: 11px;
  }
}

.strategy {
  padding: 6px 4px 10px;
  cursor: pointer;

  &:active {
    transform: scale(0.985);
    background: var(--qsc-press);
  }
}

.hero-glow {
  position: absolute;
  inset: -40% -20% auto;
  height: 140%;
  background: radial-gradient(closest-side, var(--qsc-hero-glow), transparent 70%);
  pointer-events: none;
}

.metrics {
  position: relative;
  display: flex;
  align-items: stretch;
  margin-bottom: 14px;
}

.metric {
  flex: 1;
}

.metric .value {
  font-size: 40px;
  font-weight: 760;
  letter-spacing: -1px;
  line-height: 1.05;
  font-variant-numeric: tabular-nums;
}

.metric .label {
  margin-top: 6px;
  font-size: 12px;
  color: var(--qsc-text-3);
}

.divider {
  width: 1px;
  margin: 6px 14px;
  background: var(--qsc-hairline);
}

.status-row {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 8px;
}

.updated {
  font-size: 12px;
  color: var(--qsc-text-3);
  font-variant-numeric: tabular-nums;
}

.desc {
  position: relative;
  margin: 0;
  font-size: 13px;
  color: var(--qsc-text-2);
  line-height: 1.45;
}

.switch-card {
  margin-top: 12px;
}

.strategy-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  font-size: 13px;
}

.strategy-row .k {
  color: var(--qsc-text-2);
  flex-shrink: 0;
}

.strategy-row .v {
  color: var(--qsc-text);
  text-align: right;
  font-weight: 550;
}

.go {
  padding: 4px 14px 6px;
  font-size: 12px;
  font-weight: 650;
  color: var(--qsc-primary);
}

.mini-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  padding: 16px;
}

.mini .mv {
  font-size: 18px;
  font-weight: 700;
}

.mini .ml {
  font-size: 11px;
  color: var(--qsc-text-3);
  margin-top: 2px;
}

.tips {
  margin-top: 14px;
  padding: 14px 16px;
  font-size: 13px;
  color: var(--qsc-text-2);
  line-height: 1.55;
  background: var(--qsc-surface-2);

  p {
    margin: 0 0 8px;

    &:last-child {
      margin-bottom: 0;
    }
  }
}
</style>
