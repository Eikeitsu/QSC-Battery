<script setup lang="ts">
import PresetValue from "@/shared/ui/PresetValue.vue";
import { DEFAULT_CURRENT_PRESETS, LEVEL_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";

const { store, setCurrentLevel, setCurrentUa } = useConfigFormContext();
</script>

<template>
  <div class="block-label">慢充电量</div>
  <PresetValue
    :options="LEVEL_PRESETS"
    :model-value="store.current.slow_charge"
    as-number
    label="慢充电量 %"
    placeholder="110=关闭"
    :min-display="1"
    :max-display="110"
    @update:model-value="(id) => setCurrentLevel('slow_charge', id)"
  />
  <div class="block-label">默认电流上限</div>
  <PresetValue
    :options="DEFAULT_CURRENT_PRESETS"
    :model-value="store.current.default_current_max"
    as-number
    :unit-scale="1000"
    label="默认电流 mA"
    placeholder="100–10000"
    :min-display="100"
    :max-display="10000"
    @update:model-value="(id) => setCurrentUa('default_current_max', id)"
  />
</template>

<style scoped lang="scss">
.block-label {
  font-size: 13px;
  color: var(--qsc-text-2);
  margin: 6px 0 2px;
}
</style>
