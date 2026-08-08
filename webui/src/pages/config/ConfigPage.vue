<script setup lang="ts">
import { computed, ref, watch } from "vue";
import ChipGroup from "@/shared/ui/ChipGroup.vue";
import PresetValue from "@/shared/ui/PresetValue.vue";
import ScheduleEditor from "@/shared/ui/ScheduleEditor.vue";
import ThemeSwitch from "@/shared/ui/ThemeSwitch.vue";
import AppPicker from "@/features/app-picker/AppPicker.vue";
import {
  BYPASS_TEMP_PRESETS,
  DEFAULT_CURRENT_PRESETS,
  LEVEL_PRESETS,
  LIMITS,
  ONE_LIMIT_CURRENT_PRESETS,
  POWER_START_PRESETS,
  POWER_STOP_PRESETS,
  SMALL_CURRENT_PRESETS,
  TEMP_START_PRESETS,
  TEMP_STOP_PRESETS,
  clampLevelOrOff,
  clampUa,
  type ConfigKey,
  type CurrentConfig,
} from "@/shared";
import { useAppStore, useTheme } from "@/stores";
import { showToast } from "vant";

const COLLAPSE_KEY = "qsc_current_collapse";

const store = useAppStore();
const theme = useTheme();
const showApps = ref(false);

/** 仅缓存电流控制折叠面板展开状态 */
function loadCollapse(): string[] {
  try {
    return localStorage.getItem(COLLAPSE_KEY) === "0" ? [] : ["1"];
  } catch {
    return ["1"];
  }
}
const currentOpen = ref<string[]>(loadCollapse());
watch(
  currentOpen,
  (v) => {
    try {
      localStorage.setItem(COLLAPSE_KEY, v.includes("1") ? "1" : "0");
    } catch {
      /* ignore */
    }
  },
  { deep: true },
);

const appListValue = computed(() => {
  const n = store.current.app_list?.length || 0;
  return n ? `${n} 个` : "未选";
});

const appListLabel = computed(() => {
  const n = store.current.app_list?.length || 0;
  if (!n) return "点此选择需要限流的前台应用";
  return "已选应用会在列表顶部优先显示";
});

const bypassOn = computed(() => !!Number(store.current.bypass_enable));
const tempCurrentOn = computed(() => !!Number(store.current.temperature_current));
const appLimitOn = computed(() => !!Number(store.current.app_limit));

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
  key: keyof Pick<
    CurrentConfig,
    "current_control" | "bypass_enable" | "temperature_current" | "app_limit"
  >,
  on: boolean,
) {
  store.current[key] = on ? 1 : 0;
  await store.saveCurrent();
}

async function setCurrentLevel(
  key: keyof Pick<CurrentConfig, "battery_stop" | "slow_charge" | "bypass_temp">,
  id: string | number,
) {
  const next = clampLevelOrOff(id, Number(store.current[key]));
  if (next !== Number(id)) showToast("电量/温度阈值已限制在 1–100 或 110=关闭");
  store.current[key] = next;
  await store.saveCurrent();
}

async function setCurrentUa(
  key: keyof Pick<
    CurrentConfig,
    | "default_current_max"
    | "default_current_max_limit"
    | "constant_current_max"
    | "app_current_max"
  >,
  id: string | number,
  small = false,
) {
  const maxUa: number = small ? LIMITS.uaSmallMax : LIMITS.uaMax;
  const next = clampUa(id, Number(store.current[key]), maxUa);
  if (next !== Number(id)) {
    showToast(small ? "电流已限制在 100mA–3A" : "电流已限制在 100mA–10A");
  }
  store.current[key] = next;
  await store.saveCurrent();
}

async function onBypass(mode: string | number) {
  store.current.bypass_mode = mode === "auto" ? "auto" : "sim";
  await store.saveCurrent();
}

async function onSafetyTemp() {
  const n = Number(store.current.safety_temp_max);
  const next = Math.min(
    LIMITS.safetyTempMax,
    Math.max(LIMITS.safetyTempMin, Number.isFinite(n) ? Math.round(n) : 48),
  );
  if (next !== n)
    showToast(`旁路安全温度已限制在 ${LIMITS.safetyTempMin}–${LIMITS.safetyTempMax}°C`);
  store.current.safety_temp_max = next;
  await store.saveCurrent();
}

async function onCurrentTemp(key: "default_current_limit" | "temperature_current_limit") {
  const n = Number(store.current[key]);
  const next = Math.min(
    LIMITS.currentTempMax,
    Math.max(
      LIMITS.currentTempMin,
      Number.isFinite(n) ? Math.round(n) : store.current[key],
    ),
  );
  if (next !== n)
    showToast(`温度阈值已限制在 ${LIMITS.currentTempMin}–${LIMITS.currentTempMax}°C`);
  store.current[key] = next;
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
