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
  <SectionHead title="更多选项" hint="曲线采样常用；其余冷门能力默认收起" />
  <ThemedCard>
    <van-cell
      v-if="compatHint"
      title="检测到其它充电模块"
      :label="`${compatHint} · 建议开启兼容模式`"
      is-link
      @click="onSwitch('Compatibility_mode', true)"
    />
    <SwitchCell
      title="充放电历史"
      label="供概览曲线；关闭后不再采样"
      :model-value="store.settings.history_enable === '1'"
      @update:model-value="(v) => onSwitch('history_enable', v)"
    />
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
