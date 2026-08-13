<script setup lang="ts">
import PresetValue from "@/shared/ui/PresetValue.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import { SMALL_CURRENT_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";

const {
  store,
  appLimitOn,
  onCurrentSwitch,
  setCurrentUa,
  appListLabel,
  appListValue,
  showApps,
} = useConfigFormContext();
</script>

<template>
  <SwitchCell
    title="游戏限流"
    label="进程或前台命中时限流"
    :model-value="appLimitOn"
    @update:model-value="(v) => onCurrentSwitch('app_limit', v)"
  />
  <Transition name="cfg-reveal">
    <div v-if="appLimitOn" class="reveal-block">
      <div class="block-label">游戏电流</div>
      <PresetValue
        :options="SMALL_CURRENT_PRESETS"
        :model-value="store.current.app_current_max"
        as-number
        :unit-scale="1000"
        label="游戏电流 mA"
        placeholder="100–3000"
        :min-display="100"
        :max-display="3000"
        @update:model-value="(id) => setCurrentUa('app_current_max', id, true)"
      />
      <van-cell
        title="游戏应用"
        is-link
        :label="appListLabel"
        :value="appListValue"
        @click="showApps = true"
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
