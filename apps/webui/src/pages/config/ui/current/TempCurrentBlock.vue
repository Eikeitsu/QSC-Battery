<script setup lang="ts">
import PresetValue from "@/shared/ui/PresetValue.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import { ONE_LIMIT_CURRENT_PRESETS, SMALL_CURRENT_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";

const { store, tempCurrentOn, onCurrentSwitch, onCurrentTemp, setCurrentUa } =
  useConfigFormContext();
</script>

<template>
  <SwitchCell
    title="电流温控"
    :model-value="tempCurrentOn"
    @update:model-value="(v) => onCurrentSwitch('temperature_current', v)"
  />
  <Transition name="cfg-reveal">
    <div v-if="tempCurrentOn" class="reveal-block">
      <van-field
        v-model.number="store.current.default_current_limit"
        type="digit"
        label="一限温度 °C"
        placeholder="25–60"
        input-align="right"
        @change="onCurrentTemp('default_current_limit')"
      />
      <div class="block-label">一限电流</div>
      <PresetValue
        :options="ONE_LIMIT_CURRENT_PRESETS"
        :model-value="store.current.default_current_max_limit"
        as-number
        :unit-scale="1000"
        label="一限电流 mA"
        placeholder="100–10000"
        :min-display="100"
        :max-display="10000"
        @update:model-value="(id) => setCurrentUa('default_current_max_limit', id)"
      />
      <van-field
        v-model.number="store.current.temperature_current_limit"
        type="digit"
        label="二限温度 °C"
        placeholder="25–60"
        input-align="right"
        @change="onCurrentTemp('temperature_current_limit')"
      />
      <div class="block-label">二限电流（慢充/旁路回补共用）</div>
      <PresetValue
        :options="SMALL_CURRENT_PRESETS"
        :model-value="store.current.constant_current_max"
        as-number
        :unit-scale="1000"
        label="二限电流 mA"
        placeholder="100–3000"
        :min-display="100"
        :max-display="3000"
        @update:model-value="(id) => setCurrentUa('constant_current_max', id, true)"
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
</style>
