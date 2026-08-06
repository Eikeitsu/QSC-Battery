<script setup lang="ts">
import { computed, ref } from "vue";
import ChipGroup from "../ui/ChipGroup.vue";
import ThemeSwitch from "../ui/ThemeSwitch.vue";
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
import { useAppStore, useTheme } from "../stores";

const store = useAppStore();
const theme = useTheme();
const showApps = ref(false);
const currentOpen = ref(["1"]);

const appListValue = computed(() => {
  const n = store.current.app_list?.length || 0;
  return n ? `${n} 个` : "未选";
});

const appListLabel = computed(() => {
  const n = store.current.app_list?.length || 0;
  if (!n) return "点此选择需要限流的前台应用";
  return "已选应用会在列表顶部优先显示";
});

const bypassScheduleText = computed({
  get: () => (store.current.bypass_schedule || []).join("\n"),
  set: (v: string) => {
    store.current.bypass_schedule = String(v || "")
      .split(/\n+/)
      .map((s) => s.trim())
      .filter(Boolean);
  },
});

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
  key: keyof Pick<CurrentConfig, "battery_stop" | "slow_charge" | "bypass_temp">,
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

async function saveSchedule() {
  await store.saveCurrent();
}
</script>

<template>
  <div
    class="page"
    :class="{
      'page-md3': theme.themePack === 'md3',
      'page-miuix': theme.themePack === 'miuix',
      'page-default': theme.themePack === 'default',
    }"
  >
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
        <ChipGroup
          :options="POWER_STOP_PRESETS"
          :model-value="store.settings.power_stop"
          @update:model-value="(id) => setPower('power_stop', id)"
        />
        <van-field
          v-model="store.settings.power_stop"
          type="digit"
          label="自定义停止电量"
          placeholder="1–100，110=关闭"
          input-align="right"
          @change="store.saveSettings()"
        />
        <div class="block-label">恢复电量</div>
        <ChipGroup
          :options="POWER_START_PRESETS"
          :model-value="store.settings.power_start"
          @update:model-value="(id) => setPower('power_start', id)"
        />
        <van-field
          v-model="store.settings.power_start"
          type="digit"
          label="自定义恢复电量"
          placeholder="须小于停止电量"
          input-align="right"
          @change="store.saveSettings()"
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
      <div v-if="store.settings.temperature_switch !== '0'" class="block">
        <div class="block-label">停止温度</div>
        <ChipGroup
          :options="TEMP_STOP_PRESETS"
          :model-value="store.settings.temperature_switch_stop"
          @update:model-value="(id) => setTemp('temperature_switch_stop', id)"
        />
        <van-field
          v-model="store.settings.temperature_switch_stop"
          type="digit"
          label="自定义停止温度 °C"
          input-align="right"
          @change="store.saveSettings()"
        />
        <div class="block-label">恢复温度</div>
        <ChipGroup
          :options="TEMP_START_PRESETS"
          :model-value="store.settings.temperature_switch_start"
          @update:model-value="(id) => setTemp('temperature_switch_start', id)"
        />
        <van-field
          v-model="store.settings.temperature_switch_start"
          type="digit"
          label="自定义恢复温度 °C"
          input-align="right"
          @change="store.saveSettings()"
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
            <ThemeSwitch
              :model-value="!!Number(store.current.current_control)"
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
              <div class="block-label">旁路电量（≥ 触发，110=关）</div>
              <ChipGroup
                :options="LEVEL_PRESETS"
                :model-value="String(store.current.battery_stop)"
                @update:model-value="(id) => setCurrentLevel('battery_stop', id)"
              />
              <van-field
                v-model.number="store.current.battery_stop"
                type="digit"
                label="自定义旁路电量"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <div class="block-label">旁路温度（≥ 触发，110=关）</div>
              <ChipGroup
                :options="[
                  { id: '110', l: '关闭' },
                  { id: '38', l: '38°' },
                  { id: '40', l: '40°' },
                  { id: '42', l: '42°' },
                  { id: '45', l: '45°' },
                ]"
                :model-value="String(store.current.bypass_temp)"
                @update:model-value="(id) => setCurrentLevel('bypass_temp', id)"
              />
              <van-field
                v-model.number="store.current.bypass_temp"
                type="digit"
                label="自定义旁路温度 °C"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-field
                v-model="bypassScheduleText"
                rows="2"
                autosize
                type="textarea"
                label="旁路时段"
                placeholder="每行一段，如 22:00-08:00"
                input-align="right"
                @change="saveSchedule"
              />
              <p class="field-hint">电量 / 温度 / 时段任一满足即开旁路；支持跨天</p>
              <div class="block-label">慢充电量</div>
              <ChipGroup
                :options="LEVEL_PRESETS"
                :model-value="String(store.current.slow_charge)"
                @update:model-value="(id) => setCurrentLevel('slow_charge', id)"
              />
              <van-field
                v-model.number="store.current.slow_charge"
                type="digit"
                label="自定义慢充电量"
                placeholder="110=关闭"
                input-align="right"
                @change="store.saveCurrent()"
              />
              <van-field
                v-model.number="store.current.safety_temp_max"
                type="digit"
                label="旁路安全温度 °C"
                placeholder="过热改二限小电流"
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
                  <ThemeSwitch
                    :model-value="!!Number(store.current.temperature_current)"
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
                  <ThemeSwitch
                    :model-value="!!Number(store.current.app_limit)"
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
                :label="appListLabel"
                :value="appListValue"
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
    font-weight: 600;
    color: var(--qsc-text-2);
  }

  .section-head .hint {
    font-size: 11px;
  }
}
</style>
