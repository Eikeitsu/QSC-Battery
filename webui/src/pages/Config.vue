<script setup lang="ts">
import { ref } from "vue";
import ChipGroup from "../ui/ChipGroup.vue";
import AppPicker from "../features/app-picker/AppPicker.vue";
import {
  LEVEL_PRESETS,
  POWER_START_PRESETS,
  POWER_STOP_PRESETS,
  TEMP_START_PRESETS,
  TEMP_STOP_PRESETS,
  type ConfigKey,
  type CurrentConfig,
} from "../shared";
import { useAppStore } from "../stores";

const store = useAppStore();
const showApps = ref(false);
const currentOpen = ref(["1"]);

async function setPower(key: ConfigKey, id: string | number) {
  store.settings[key] = String(id);
  await store.saveSettings();
}

async function setTemp(key: ConfigKey, id: string | number) {
  store.settings[key] = String(id);
  await store.saveSettings();
}

async function onSwitch(key: ConfigKey, on: boolean) {
  store.settings[key] = on ? "1" : "0";
  await store.saveSettings();
}

async function onCurrentSwitch(
  key: keyof Pick<CurrentConfig, "current_control" | "temperature_current" | "app_limit">,
  on: boolean,
) {
  store.current[key] = on ? 1 : 0;
  await store.saveCurrent();
}

async function setCurrentLevel(
  key: keyof Pick<CurrentConfig, "battery_stop" | "slow_charge">,
  id: string | number,
) {
  store.current[key] = Number(id);
  await store.saveCurrent();
}

async function onBypass(mode: string | number) {
  store.current.bypass_mode = mode === "auto" ? "auto" : "sim";
  await store.saveCurrent();
}

async function onAppsSaved() {
  await store.saveCurrent();
}
</script>

<template>
  <div class="page">
    <div class="section-head">
      <p class="title">电量停充</p>
      <p class="hint">到达阈值后停止充电，掉到恢复值再继续</p>
    </div>
    <section class="card">
      <div class="block">
        <div class="block-label">停止电量 · {{ store.powerPlan }}</div>
        <ChipGroup
          :options="POWER_STOP_PRESETS"
          :model-value="store.settings.power_stop"
          @update:model-value="(id) => setPower('power_stop', id)"
        />
        <div class="block-label">恢复电量</div>
        <ChipGroup
          :options="POWER_START_PRESETS"
          :model-value="store.settings.power_start"
          @update:model-value="(id) => setPower('power_start', id)"
        />
        <van-field
          v-model="store.settings.power_stop_time"
          type="digit"
          label="延时秒数"
          input-align="right"
          @change="store.saveSettings()"
        />
      </div>
      <van-cell center title="充满再停" label="100% 时等涓流结束再停充">
        <template #right-icon>
          <van-switch
            :model-value="store.settings.charge_full === '1'"
            size="22px"
            @update:model-value="(v) => onSwitch('charge_full', v)"
          />
        </template>
      </van-cell>
      <van-cell center title="自动拔插" label="插电时模拟拔插以激活快充">
        <template #right-icon>
          <van-switch
            :model-value="store.settings.power_reset === '1'"
            size="22px"
            @update:model-value="(v) => onSwitch('power_reset', v)"
          />
        </template>
      </van-cell>
      <van-cell center title="兼容模式" label="与其它快充 / 限流模块同装时建议开启">
        <template #right-icon>
          <van-switch
            :model-value="store.settings.Compatibility_mode === '1'"
            size="22px"
            @update:model-value="(v) => onSwitch('Compatibility_mode', v)"
          />
        </template>
      </van-cell>
    </section>

    <div class="section-head">
      <p class="title">温控停充</p>
      <p class="hint">电池过热时暂停，降温后再恢复</p>
    </div>
    <section class="card">
      <van-cell center title="温控开关" :label="store.tempPlan">
        <template #right-icon>
          <van-switch
            :model-value="store.settings.temperature_switch !== '0'"
            size="22px"
            @update:model-value="(v) => onSwitch('temperature_switch', v)"
          />
        </template>
      </van-cell>
      <div v-if="store.settings.temperature_switch !== '0'" class="block">
        <div class="block-label">停止温度</div>
        <ChipGroup
          :options="TEMP_STOP_PRESETS"
          :model-value="store.settings.temperature_switch_stop"
          @update:model-value="(id) => setTemp('temperature_switch_stop', id)"
        />
        <div class="block-label">恢复温度</div>
        <ChipGroup
          :options="TEMP_START_PRESETS"
          :model-value="store.settings.temperature_switch_start"
          @update:model-value="(id) => setTemp('temperature_switch_start', id)"
        />
      </div>
    </section>

    <template v-if="store.currentFeature">
      <div class="section-head">
        <p class="title">电流控制</p>
        <p class="hint">旁路、慢充与游戏限流（可选安装）</p>
      </div>
      <section class="card">
        <van-cell center title="电流控制总开关" :label="store.currentPlan">
          <template #right-icon>
            <van-switch
              :model-value="!!Number(store.current.current_control)"
              size="22px"
              @update:model-value="(v) => onCurrentSwitch('current_control', v)"
            />
          </template>
        </van-cell>
        <van-collapse v-if="Number(store.current.current_control)" v-model="currentOpen">
          <van-collapse-item name="1" title="旁路 / 慢充 / 限流">
            <div class="block nested">
              <div class="block-label">旁路方式</div>
              <ChipGroup
                :options="[
                  { id: 'sim', l: '模拟写电流' },
                  { id: 'auto', l: '自动节点' },
                ]"
                :model-value="store.current.bypass_mode"
                @update:model-value="onBypass"
              />
              <div class="block-label">模拟旁路电量</div>
              <ChipGroup
                :options="LEVEL_PRESETS"
                :model-value="String(store.current.battery_stop)"
                @update:model-value="(id) => setCurrentLevel('battery_stop', id)"
              />
              <div class="block-label">慢充电量</div>
              <ChipGroup
                :options="LEVEL_PRESETS"
                :model-value="String(store.current.slow_charge)"
                @update:model-value="(id) => setCurrentLevel('slow_charge', id)"
              />
              <van-field
                v-model.number="store.current.safety_temp_max"
                type="digit"
                label="旁路安全温度"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-field
                v-model.number="store.current.default_current_max"
                type="digit"
                label="默认电流上限 μA"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-cell center title="电流温控">
                <template #right-icon>
                  <van-switch
                    :model-value="!!Number(store.current.temperature_current)"
                    size="22px"
                    @update:model-value="(v) => onCurrentSwitch('temperature_current', v)"
                  />
                </template>
              </van-cell>
              <van-field
                v-model.number="store.current.default_current_limit"
                type="digit"
                label="一限温度 °C"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-field
                v-model.number="store.current.default_current_max_limit"
                type="digit"
                label="一限电流 μA"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-field
                v-model.number="store.current.temperature_current_limit"
                type="digit"
                label="二限温度 °C"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-field
                v-model.number="store.current.constant_current_max"
                type="digit"
                label="二限电流 μA"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-cell center title="游戏限流" label="仅匹配前台窗口">
                <template #right-icon>
                  <van-switch
                    :model-value="!!Number(store.current.app_limit)"
                    size="22px"
                    @update:model-value="(v) => onCurrentSwitch('app_limit', v)"
                  />
                </template>
              </van-cell>
              <van-field
                v-model.number="store.current.app_current_max"
                type="digit"
                label="游戏电流 μA"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-cell
                title="游戏应用"
                is-link
                :value="`${store.current.app_list?.length || 0} 个`"
                @click="showApps = true"
              />
            </div>
          </van-collapse-item>
        </van-collapse>
      </section>
    </template>

    <AppPicker
      v-model:show="showApps"
      v-model="store.current.app_list"
      @saved="onAppsSaved"
    />
  </div>
</template>

<style scoped lang="scss">
.block {
  padding: 12px 16px 8px;
}

.block.nested {
  padding-top: 4px;
}

.block-label {
  font-size: 13px;
  color: var(--qsc-text-2);
  margin: 6px 0 2px;
}
</style>
