<script setup lang="ts">
import PresetValue from "@/shared/ui/PresetValue.vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import ScheduleEditor from "@/shared/ui/ScheduleEditor.vue";
import { POWER_START_PRESETS, POWER_STOP_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";
import ConfigBlock from "./ConfigBlock.vue";

const { store, setPower, onSwitch, savePowerStopSchedule } = useConfigFormContext();
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
        @update:model-value="(id) => setPower('power_stop', id)"
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
        @change="store.saveSettings()"
      />
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
      label="100% 时等涓流结束再停充"
      :model-value="store.settings.charge_full === '1'"
      @update:model-value="(v) => onSwitch('charge_full', v)"
    />
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
</style>
