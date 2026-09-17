<script setup lang="ts">
import PresetValue from "@/shared/ui/PresetValue.vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { TEMP_START_PRESETS, TEMP_STOP_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";
import ConfigBlock from "./ConfigBlock.vue";

const { store, setTemp, onSwitch } = useConfigFormContext();
</script>

<template>
  <SectionHead title="温控停充" hint="电池过热时暂停，降温后再恢复" />
  <ThemedCard>
    <SwitchCell
      title="温控开关"
      :label="store.tempPlan"
      :model-value="store.settings.temperature_switch !== '0'"
      @update:model-value="(v) => onSwitch('temperature_switch', v)"
    />
    <Transition name="cfg-reveal">
      <ConfigBlock v-if="store.settings.temperature_switch !== '0'" label="停止温度">
        <PresetValue
          :options="TEMP_STOP_PRESETS"
          :model-value="store.settings.temperature_switch_stop"
          label="停止温度 °C"
          :min-display="25"
          :max-display="70"
          @update:model-value="(id) => setTemp('temperature_switch_stop', id)"
        />
        <div class="block-label">恢复温度</div>
        <PresetValue
          :options="TEMP_START_PRESETS"
          :model-value="store.settings.temperature_switch_start"
          label="恢复温度 °C"
          :min-display="25"
          :max-display="70"
          @update:model-value="(id) => setTemp('temperature_switch_start', id)"
        />
      </ConfigBlock>
    </Transition>
  </ThemedCard>
</template>

<style scoped lang="scss">
.block-label {
  font-size: 13px;
  color: var(--qsc-text-2);
  margin: 6px 0 2px;
}
</style>
