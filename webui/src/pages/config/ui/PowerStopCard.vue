<script setup lang="ts">
import PresetValue from "@/shared/ui/PresetValue.vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { POWER_START_PRESETS, POWER_STOP_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";
import ConfigBlock from "./ConfigBlock.vue";

const { store, setPower, onSwitch } = useConfigFormContext();
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
    <SwitchCell
      title="充满再停"
      label="100% 时等涓流结束再停充"
      :model-value="store.settings.charge_full === '1'"
      @update:model-value="(v) => onSwitch('charge_full', v)"
    />
    <SwitchCell
      title="自动拔插"
      label="插电时模拟拔插以激活快充"
      :model-value="store.settings.power_reset === '1'"
      @update:model-value="(v) => onSwitch('power_reset', v)"
    />
    <SwitchCell
      title="兼容模式"
      label="与其它快充 / 限流模块同装时建议开启"
      :model-value="store.settings.Compatibility_mode === '1'"
      @update:model-value="(v) => onSwitch('Compatibility_mode', v)"
    />
  </ThemedCard>
</template>

<style scoped lang="scss">
.block-label {
  font-size: 13px;
  color: var(--qsc-text-2);
  margin: 6px 0 2px;
}
</style>
