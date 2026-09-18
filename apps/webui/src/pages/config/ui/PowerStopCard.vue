<script setup lang="ts">
import { computed, watch } from "vue";
import { showToast } from "vant";
import ChipGroup from "@/shared/ui/ChipGroup.vue";
import PresetValue from "@/shared/ui/PresetValue.vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import ScheduleEditor from "@/shared/ui/ScheduleEditor.vue";
import { POWER_START_PRESETS, POWER_STOP_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";
import ConfigBlock from "./ConfigBlock.vue";

const { store, setPower, onSwitch, savePowerStopSchedule } = useConfigFormContext();

const stopIsFull = computed(() => String(store.settings.power_stop) === "100");
const chargeFullOn = computed(
  () => store.settings.charge_full === "1" && stopIsFull.value,
);

const modeChipOptions = [
  { id: "auto", l: "自动" },
  { id: "current", l: "电流" },
  { id: "time", l: "时间" },
];

const modeHint = computed(() => {
  switch (store.settings.charge_full_mode) {
    case "time":
      return "进入 100% 后再等约 10 分钟再停（时长仅能改配置文件 charge_full_wait_sec）";
    case "current":
      return "电流持续偏低（约 |I|<100mA 连续若干轮）后再停";
    default:
      return "电流或时间任一满足即停（时间约 10 分钟）";
  }
});

async function setPowerStop(id: string | number) {
  await setPower("power_stop", String(id));
  if (String(id) !== "100" && store.settings.charge_full === "1") {
    store.settings.charge_full = "0";
    await store.saveSettings();
    showToast("停止电量不是 100%，已关闭充满再停");
  }
}

async function onChargeFull(on: boolean) {
  if (on && !stopIsFull.value) {
    showToast("充满再停仅在停止电量为 100% 时可用");
    return;
  }
  await onSwitch("charge_full", on);
}

async function onModeChange(v: string | number) {
  const mode = String(v);
  store.settings.charge_full_mode =
    mode === "time" || mode === "current" || mode === "auto" ? mode : "auto";
  await store.saveSettings();
}

watch(stopIsFull, async (ok) => {
  if (!ok && store.settings.charge_full === "1") {
    store.settings.charge_full = "0";
    await store.saveSettings();
  }
});
</script>

<template>
  <SectionHead title="电量停充" hint="到达阈值后停止充电，掉到恢复值再继续" />
  <ThemedCard>
    <ConfigBlock :label="`停止电量 · ${store.powerPlan}`">
      <PresetValue
        :options="POWER_STOP_PRESETS"
        :model-value="store.settings.power_stop"
        label="停止电量 %"
        placeholder="1–100，110=关闭"
        :min-display="1"
        :max-display="110"
        @update:model-value="setPowerStop"
      />
      <div class="block-label">恢复电量</div>
      <PresetValue
        :options="POWER_START_PRESETS"
        :model-value="store.settings.power_start"
        label="恢复电量 %"
        placeholder="须小于停止电量"
        :min-display="1"
        :max-display="100"
        @update:model-value="(id) => setPower('power_start', id)"
      />
      <van-field
        v-model="store.settings.power_stop_time"
        type="digit"
        label="延时秒数"
        placeholder="1–120"
        input-align="right"
        :disabled="chargeFullOn"
        @change="store.saveSettings()"
      />
      <p v-if="chargeFullOn" class="field-hint">充满再停开启时延时停充不生效</p>
    </ConfigBlock>
    <ConfigBlock label="停充时段（可选）">
      <p class="field-hint">留空全天生效；填写后仅在时段内按电量停充</p>
      <ScheduleEditor
        v-model="store.powerStopSchedule"
        add-title="添加停充时段"
        edit-title="编辑停充时段"
        @change="savePowerStopSchedule"
      />
    </ConfigBlock>
    <SwitchCell
      title="充满再停"
      :label="
        stopIsFull
          ? '仅停止电量=100% 时可用：到 100% 后等涓流再停'
          : '需先把停止电量设为 100% 才能开启'
      "
      :model-value="chargeFullOn"
      :disabled="!stopIsFull"
      @update:model-value="onChargeFull"
    />
    <template v-if="chargeFullOn">
      <div class="trickle-block">
        <div class="trickle-title">涓流模式</div>
        <p class="field-hint">{{ modeHint }}</p>
        <ChipGroup
          :options="modeChipOptions"
          :model-value="store.settings.charge_full_mode || 'auto'"
          @update:model-value="onModeChange"
        />
      </div>
    </template>
  </ThemedCard>
</template>

<style scoped lang="scss">
.block-label {
  font-size: 13px;
  color: var(--qsc-text-2);
  margin: 6px 0 2px;
}

.field-hint {
  margin: 0 0 8px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.4;
  padding: 0 var(--qsc-cell-pad-x, 4px);
}

.trickle-block {
  padding: 4px var(--qsc-cell-pad-x, 16px) 4px;
}

.trickle-title {
  font-size: 15px;
  font-weight: 500;
  color: var(--qsc-text);
  margin-bottom: 2px;
}
</style>
