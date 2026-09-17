<script setup lang="ts">
import ChipGroup from "@/shared/ui/ChipGroup.vue";
import PresetValue from "@/shared/ui/PresetValue.vue";
import ScheduleEditor from "@/shared/ui/ScheduleEditor.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import { BYPASS_MODE_PRESETS, BYPASS_TEMP_PRESETS, LEVEL_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";

const {
  store,
  bypassOn,
  onCurrentSwitch,
  onBypass,
  setCurrentLevel,
  saveSchedule,
  onSafetyTemp,
} = useConfigFormContext();
</script>

<template>
  <SwitchCell
    title="旁路"
    label="电量 / 温度 / 时段触发"
    :model-value="bypassOn"
    @update:model-value="(v) => onCurrentSwitch('bypass_enable', v)"
  />
  <Transition name="cfg-reveal">
    <div v-if="bypassOn" class="reveal-block">
      <div class="block-label">旁路方式</div>
      <ChipGroup
        :options="BYPASS_MODE_PRESETS"
        :model-value="store.current.bypass_mode"
        @update:model-value="onBypass"
      />
      <div class="block-label">旁路电量（≥ 触发，110=关）</div>
      <PresetValue
        :options="LEVEL_PRESETS"
        :model-value="store.current.battery_stop"
        as-number
        label="旁路电量 %"
        :min-display="1"
        :max-display="110"
        @update:model-value="(id) => setCurrentLevel('battery_stop', id)"
      />
      <div class="block-label">旁路温度（≥ 触发，110=关）</div>
      <PresetValue
        :options="BYPASS_TEMP_PRESETS"
        :model-value="store.current.bypass_temp"
        as-number
        label="旁路温度 °C"
        :min-display="1"
        :max-display="110"
        @update:model-value="(id) => setCurrentLevel('bypass_temp', id)"
      />
      <div class="block-label">旁路时段</div>
      <ScheduleEditor v-model="store.current.bypass_schedule" @change="saveSchedule" />
      <p class="field-hint">电量 / 温度 / 时段任一满足即开旁路；支持跨天</p>
      <van-field
        v-model.number="store.current.safety_temp_max"
        type="digit"
        label="旁路安全温度 °C"
        placeholder="40–55"
        input-align="right"
        @change="onSafetyTemp"
      />
    </div>
  </Transition>
</template>

<style scoped lang="scss">
.reveal-block {
  overflow: hidden;
}

.block-label {
  font-size: 13px;
  color: var(--qsc-text-2);
  margin: 6px 0 2px;
}

.field-hint {
  margin: 4px 0 8px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.4;
}
</style>
