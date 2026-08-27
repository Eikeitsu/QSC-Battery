<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { useConfigFormContext } from "@/composables";
import * as api from "@/shared/api";

const { store, onSwitch } = useConfigFormContext();
const compatHint = ref("");
/** 冷门项默认收起 */
const nicheOpen = ref<string[]>([]);
/** 重新打开曲线后提示一次：采样不会跟着自动打开，由用户决定 */
const chartJustEnabled = ref(false);

const samplingLabel = computed(() =>
  store.settings.chart_show === "0"
    ? "曲线已关闭，采样同时停止"
    : "仅充电时采样，用于曲线上的电流线；关闭后曲线只用系统电池记录",
);

const samplingHint = computed(() => {
  if (store.settings.chart_show === "0") return "";
  if (!chartJustEnabled.value) return "";
  if (store.settings.history_enable === "1") return "";
  return "曲线已重新显示。采样仍是关闭的：不开也能看电量与温度线（数据来自系统电池记录），开了才有充电电流线，是否开启由你决定。";
});

async function setChartShow(show: boolean) {
  store.settings.chart_show = show ? "1" : "0";
  // 关闭曲线时连采样一起停，避免"看不见还在写盘"；重新打开不自动开采样
  if (!show) store.settings.history_enable = "0";
  chartJustEnabled.value = show;
  await store.saveSettings();
}

const wirelessIgnore = computed(() => store.settings.wireless_policy === "ignore");

async function setWireless(ignore: boolean) {
  store.settings.wireless_policy = ignore ? "ignore" : "same";
  await store.saveSettings();
}

async function saveField() {
  await store.saveSettings();
}

onMounted(async () => {
  compatHint.value = await api.loadCompatHint();
});
</script>

<template>
  <SectionHead title="更多选项" hint="省电与曲线采样常用；其余冷门能力默认收起" />
  <ThemedCard>
    <SwitchCell
      title="省电模式"
      label="按场景切换轮询间隔，明显降低待机耗电；关闭则全程用最短间隔"
      :model-value="store.settings.power_saver !== '0'"
      @update:model-value="(v) => onSwitch('power_saver', v)"
    />
    <template v-if="store.settings.power_saver !== '0'">
      <van-field
        v-model="store.settings.loop_interval_idle_sec"
        type="digit"
        label="未插电间隔(秒)"
        placeholder="3–300，越大越省电"
        input-align="right"
        @change="saveField"
      />
      <van-field
        v-model="store.settings.loop_interval_plugged_sec"
        type="digit"
        label="插电间隔(秒)"
        placeholder="2–120，离阈值远时"
        input-align="right"
        @change="saveField"
      />
      <van-field
        v-model="store.settings.loop_interval_near_window"
        type="digit"
        label="临近阈值窗口(%)"
        placeholder="1–20，窗口内用最短间隔"
        input-align="right"
        @change="saveField"
      />
      <p class="warn">
        未插电时最多延迟「未插电间隔」才会发现插上了充电器；电量进入停充阈值前
        {{ store.settings.loop_interval_near_window || 3 }}% 后自动切回
        {{ store.settings.loop_interval_sec || 3 }} 秒轮询，不影响停充准确度。
      </p>
    </template>
    <van-cell
      v-if="compatHint"
      title="检测到其它充电模块"
      :label="`${compatHint} · 建议开启兼容模式`"
      is-link
      @click="onSwitch('Compatibility_mode', true)"
    />
    <SwitchCell
      title="显示充放电曲线"
      label="关闭后概览页不再显示曲线，并一并停止采样"
      :model-value="store.settings.chart_show !== '0'"
      @update:model-value="setChartShow"
    />
    <SwitchCell
      title="充放电历史采样"
      :label="samplingLabel"
      :model-value="store.settings.history_enable === '1'"
      :disabled="store.settings.chart_show === '0'"
      @update:model-value="(v) => onSwitch('history_enable', v)"
    />
    <p v-if="samplingHint" class="warn">{{ samplingHint }}</p>
    <van-field
      v-if="store.settings.history_enable === '1'"
      v-model="store.settings.history_interval_sec"
      type="digit"
      label="采样间隔(秒)"
      placeholder="15–600"
      input-align="right"
      @change="saveField"
    />

    <van-collapse v-model="nicheOpen" accordion>
      <van-collapse-item name="niche" title="冷门 / 实验（一般不用）">
        <p class="warn">
          下列项面向排障或特殊机型。日常请优先用电量/温控停充与电流控制里的游戏限流。
        </p>
        <van-field
          v-model="store.settings.loop_interval_sec"
          type="digit"
          label="循环间隔(秒)"
          placeholder="2–30"
          input-align="right"
          @change="saveField"
        />
        <van-field
          v-model="store.settings.loop_interval_maintain_sec"
          type="digit"
          label="停充维持间隔"
          placeholder="3–60"
          input-align="right"
          @change="saveField"
        />
        <van-field
          v-model="store.settings.switch_verify_sec"
          type="digit"
          label="停充校验等待"
          placeholder="0–5 秒"
          input-align="right"
          @change="saveField"
        />
        <SwitchCell
          title="无线时忽略停充策略"
          label="仅无线供电不触发阈值/温控停充"
          :model-value="wirelessIgnore"
          @update:model-value="setWireless"
        />
        <SwitchCell
          title="按 App 硬停充"
          label="不推荐：易误触；游戏请用「电流控制 → 游戏限流」"
          :model-value="store.settings.app_stop === '1'"
          @update:model-value="(v) => onSwitch('app_stop', v)"
        />
        <van-field
          v-if="store.settings.app_stop === '1'"
          v-model="store.settings.app_stop_list"
          rows="2"
          autosize
          type="textarea"
          label="包名列表"
          placeholder="逗号分隔包名"
          @change="saveField"
        />
      </van-collapse-item>
    </van-collapse>
  </ThemedCard>
</template>

<style scoped lang="scss">
.warn {
  margin: 0;
  padding: 8px var(--qsc-cell-pad-x, 16px) 12px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.45;
}

:deep(.van-collapse-item__content) {
  padding: 0;
}

:deep(.van-cell) {
  background: transparent;
}
</style>
