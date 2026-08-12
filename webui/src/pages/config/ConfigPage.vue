<script setup lang="ts">
import ChipGroup from "@/shared/ui/ChipGroup.vue";
import PresetValue from "@/shared/ui/PresetValue.vue";
import ScheduleEditor from "@/shared/ui/ScheduleEditor.vue";
import ThemeSwitch from "@/shared/ui/ThemeSwitch.vue";
import AppPicker from "@/features/app-picker/AppPicker.vue";
import {
  BYPASS_TEMP_PRESETS,
  DEFAULT_CURRENT_PRESETS,
  LEVEL_PRESETS,
  ONE_LIMIT_CURRENT_PRESETS,
  POWER_START_PRESETS,
  POWER_STOP_PRESETS,
  SMALL_CURRENT_PRESETS,
  TEMP_START_PRESETS,
  TEMP_STOP_PRESETS,
} from "@/shared";
import { useConfigForm, useThemePackClass } from "@/composables";

const { theme, packClass } = useThemePackClass();
const {
  store,
  showApps,
  currentOpen,
  appListValue,
  appListLabel,
  bypassOn,
  tempCurrentOn,
  appLimitOn,
  setPower,
  setTemp,
  onSwitch,
  onCurrentSwitch,
  setCurrentLevel,
  setCurrentUa,
  onBypass,
  onSafetyTemp,
  onCurrentTemp,
  onAppsSaved,
  saveSchedule,
} = useConfigForm();
</script>

<template>
  <div class="page" :class="packClass">
    <div class="section-head" :class="{ 'miuix-sec': theme.themePack === 'miuix' }">
      <p class="title">电量停充</p>
      <p class="hint">到达阈值后停止充电，掉到恢复值再继续</p>
    </div>
    <section
      class="card"
      :class="{
        'md3-tonal': theme.themePack === 'md3',
        'miuix-card': theme.themePack === 'miuix',
      }"
    >
      <div class="block">
        <div class="block-label">停止电量 · {{ store.powerPlan }}</div>
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
      </div>
      <van-cell center title="充满再停" label="100% 时等涓流结束再停充">
        <template #right-icon>
          <ThemeSwitch
            :model-value="store.settings.charge_full === '1'"
            @update:model-value="(v) => onSwitch('charge_full', v)"
          />
        </template>
      </van-cell>
      <van-cell center title="自动拔插" label="插电时模拟拔插以激活快充">
        <template #right-icon>
          <ThemeSwitch
            :model-value="store.settings.power_reset === '1'"
            @update:model-value="(v) => onSwitch('power_reset', v)"
          />
        </template>
      </van-cell>
      <van-cell center title="兼容模式" label="与其它快充 / 限流模块同装时建议开启">
        <template #right-icon>
          <ThemeSwitch
            :model-value="store.settings.Compatibility_mode === '1'"
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
          <ThemeSwitch
            :model-value="store.settings.temperature_switch !== '0'"
            @update:model-value="(v) => onSwitch('temperature_switch', v)"
          />
        </template>
      </van-cell>
      <Transition name="cfg-reveal">
        <div v-if="store.settings.temperature_switch !== '0'" class="block reveal-block">
          <div class="block-label">停止温度</div>
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
        </div>
      </Transition>
    </section>

    <template v-if="store.currentFeature">
      <div class="section-head">
        <p class="title">电流控制</p>
        <p class="hint">旁路、慢充与游戏限流（可选安装）</p>
      </div>
      <section class="card">
        <van-cell center title="电流控制总开关" :label="store.currentPlan">
          <template #right-icon>
            <ThemeSwitch
              :model-value="!!Number(store.current.current_control)"
              @update:model-value="(v) => onCurrentSwitch('current_control', v)"
            />
          </template>
        </van-cell>
        <Transition name="cfg-reveal">
          <van-collapse
            v-if="Number(store.current.current_control)"
            v-model="currentOpen"
          >
            <van-collapse-item name="1" title="旁路 / 慢充 / 限流">
              <div class="block nested">
                <van-cell center title="旁路" label="电量 / 温度 / 时段触发">
                  <template #right-icon>
                    <ThemeSwitch
                      :model-value="bypassOn"
                      @update:model-value="(v) => onCurrentSwitch('bypass_enable', v)"
                    />
                  </template>
                </van-cell>
                <Transition name="cfg-reveal">
                  <div v-if="bypassOn" class="reveal-block">
                    <div class="block-label">旁路方式</div>
                    <ChipGroup
                      :options="[
                        { id: 'sim', l: '模拟写电流' },
                        { id: 'auto', l: '自动节点' },
                      ]"
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
                    <ScheduleEditor
                      v-model="store.current.bypass_schedule"
                      @change="saveSchedule"
                    />
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
                <van-cell center title="电流温控">
                  <template #right-icon>
                    <ThemeSwitch
                      :model-value="tempCurrentOn"
                      @update:model-value="
                        (v) => onCurrentSwitch('temperature_current', v)
                      "
                    />
                  </template>
                </van-cell>
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
                      @update:model-value="
                        (id) => setCurrentUa('default_current_max_limit', id)
                      "
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
                      @update:model-value="
                        (id) => setCurrentUa('constant_current_max', id, true)
                      "
                    />
                  </div>
                </Transition>
                <van-cell center title="游戏限流" label="进程或前台命中时限流">
                  <template #right-icon>
                    <ThemeSwitch
                      :model-value="appLimitOn"
                      @update:model-value="(v) => onCurrentSwitch('app_limit', v)"
                    />
                  </template>
                </van-cell>
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
                      @update:model-value="
                        (id) => setCurrentUa('app_current_max', id, true)
                      "
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
              </div>
            </van-collapse-item>
          </van-collapse>
        </Transition>
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
  padding: 12px var(--qsc-cell-pad-x, 16px) 8px;
}

.block.nested {
  padding-top: 4px;
}

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

.page-md3 {
  .section-head {
    margin: 20px 4px 12px;
  }

  .section-head .title {
    font-size: 13px;
    font-weight: 600;
    color: var(--qsc-text-2);
    letter-spacing: 0.02em;
  }

  .card {
    margin-bottom: 4px;
  }
}

.page-miuix {
  .section-head {
    margin: 16px 10px 8px;
  }

  .section-head .title {
    font-size: 13px;
  }
}
</style>
