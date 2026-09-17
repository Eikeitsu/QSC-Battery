import { computed, inject, provide, ref, watch, type InjectionKey } from "vue";
import { showToast } from "vant";
import {
  BinaryFlag,
  BypassMode,
  CURRENT_DEFAULTS,
  LIMITS,
  STORAGE_KEYS,
  clampLevelOrOff,
  clampUa,
  isBypassMode,
  readStorage,
  writeStorageFlag,
  type ConfigKey,
  type CurrentConfig,
} from "@/shared";
import { useAppStore } from "@/stores";

type CurrentSwitchKey = keyof Pick<
  CurrentConfig,
  "current_control" | "bypass_enable" | "temperature_current" | "app_limit"
>;
type CurrentLevelKey = keyof Pick<
  CurrentConfig,
  "battery_stop" | "slow_charge" | "bypass_temp"
>;
type CurrentUaKey = keyof Pick<
  CurrentConfig,
  | "default_current_max"
  | "default_current_max_limit"
  | "constant_current_max"
  | "app_current_max"
>;

function loadCollapse(): string[] {
  return readStorage(STORAGE_KEYS.currentCollapse) === BinaryFlag.Off
    ? []
    : [BinaryFlag.On];
}

export function useConfigForm() {
  const store = useAppStore();
  const showApps = ref(false);
  const currentOpen = ref<string[]>(loadCollapse());

  watch(
    currentOpen,
    (v) => {
      writeStorageFlag(STORAGE_KEYS.currentCollapse, v.includes(BinaryFlag.On));
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
    store.settings[key] = on ? BinaryFlag.On : BinaryFlag.Off;
    await store.saveSettings();
  }

  async function onCurrentSwitch(key: CurrentSwitchKey, on: boolean) {
    store.current[key] = on ? 1 : 0;
    await store.saveCurrent();
  }

  async function setCurrentLevel(key: CurrentLevelKey, id: string | number) {
    const next = clampLevelOrOff(id, Number(store.current[key]));
    if (next !== Number(id)) showToast("电量/温度阈值已限制在 1–100 或 110=关闭");
    store.current[key] = next;
    await store.saveCurrent();
  }

  async function setCurrentUa(key: CurrentUaKey, id: string | number, small = false) {
    const maxUa: number = small ? LIMITS.uaSmallMax : LIMITS.uaMax;
    const next = clampUa(id, Number(store.current[key]), maxUa);
    if (next !== Number(id)) {
      showToast(small ? "电流已限制在 100mA–3A" : "电流已限制在 100mA–10A");
    }
    store.current[key] = next;
    await store.saveCurrent();
  }

  async function onBypass(mode: string | number) {
    store.current.bypass_mode = isBypassMode(mode) ? mode : BypassMode.Sim;
    await store.saveCurrent();
  }

  async function onSafetyTemp() {
    const n = Number(store.current.safety_temp_max);
    const next = Math.min(
      LIMITS.safetyTempMax,
      Math.max(
        LIMITS.safetyTempMin,
        Number.isFinite(n) ? Math.round(n) : CURRENT_DEFAULTS.safety_temp_max,
      ),
    );
    if (next !== n)
      showToast(`旁路安全温度已限制在 ${LIMITS.safetyTempMin}–${LIMITS.safetyTempMax}°C`);
    store.current.safety_temp_max = next;
    await store.saveCurrent();
  }

  async function onCurrentTemp(
    key: "default_current_limit" | "temperature_current_limit",
  ) {
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

  async function savePowerStopSchedule() {
    await store.savePowerStopSchedule();
  }

  async function saveNotifyQuietSchedule() {
    await store.saveNotifyQuietSchedule();
  }

  const powerSwitchText = computed({
    get: () => (store.powerSwitches || []).join("\n"),
    set: (v: string) => {
      store.powerSwitches = String(v || "")
        .split(/\r?\n/)
        .map((l) => l.trim())
        .filter(Boolean);
    },
  });

  async function savePowerSwitches() {
    await store.savePowerSwitchText();
  }

  return {
    store,
    showApps,
    currentOpen,
    appListValue,
    appListLabel,
    bypassOn,
    tempCurrentOn,
    appLimitOn,
    powerSwitchText,
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
    savePowerStopSchedule,
    saveNotifyQuietSchedule,
    savePowerSwitches,
  };
}

export type ConfigFormApi = ReturnType<typeof useConfigForm>;
export const CONFIG_FORM_KEY: InjectionKey<ConfigFormApi> = Symbol("qsc-config-form");

export function provideConfigForm() {
  const api = useConfigForm();
  provide(CONFIG_FORM_KEY, api);
  return api;
}

export function useConfigFormContext() {
  const api = inject(CONFIG_FORM_KEY);
  if (!api) throw new Error("useConfigFormContext() 需在 ConfigPage 内使用");
  return api;
}
