import { showSuccessToast, showToast } from "vant";
import {
  CONFIG_KEYS,
  CURRENT_DEFAULTS,
  DEFAULTS,
  DEVICE_INFO_SHELL,
  PATHS,
  BinaryFlag,
  formatDeviceLabel,
  sanitizeSettings,
  type ConfigKey,
  type CurrentConfig,
  type Settings,
} from "@/shared";
import * as api from "@/shared/api";
import type { Ref } from "vue";

export type ConfigActionsCtx = {
  settings: Settings;
  current: CurrentConfig;
  powerSwitches: Ref<string[]>;
  powerStopSchedule: Ref<string[]>;
  notifyQuietSchedule: Ref<string[]>;
  nightSchedule: Ref<string[]>;
  currentFeature: Ref<boolean>;
  deviceName: Ref<string>;
  status: { moduleOn: boolean };
  refreshStatus: () => Promise<void>;
};

export function createConfigActions(ctx: ConfigActionsCtx) {
  const {
    settings,
    current,
    powerSwitches,
    powerStopSchedule,
    notifyQuietSchedule,
    nightSchedule,
    currentFeature,
    deviceName,
    status,
    refreshStatus,
  } = ctx;

  async function loadDeviceInfo(): Promise<void> {
    if (!api.hasBridge()) {
      deviceName.value = "WebUI 桥接不可用";
      return;
    }
    const info = await api.exec(DEVICE_INFO_SHELL);
    deviceName.value = formatDeviceLabel(info.stdout);
  }

  async function loadConfig(): Promise<void> {
    const [values, switches, stopSchedule, quietSchedule, night] = await Promise.all([
      api.loadConfigValues(CONFIG_KEYS),
      api.loadPowerSwitches(),
      api.loadPowerStopSchedule(),
      api.loadNotifyQuietSchedule(),
      api.loadNightSchedule(),
    ]);
    CONFIG_KEYS.forEach((key) => {
      settings[key] = values[key] || DEFAULTS[key];
    });
    powerSwitches.value = switches;
    powerStopSchedule.value = stopSchedule;
    notifyQuietSchedule.value = quietSchedule;
    nightSchedule.value = night;
  }

  async function loadCurrentConfig(): Promise<void> {
    currentFeature.value = await api.hasCurrentFeature();
    if (!currentFeature.value) {
      Object.assign(current, CURRENT_DEFAULTS);
      return;
    }
    Object.assign(current, await api.loadCurrentJsonc());
  }

  async function saveSettings(toast = true): Promise<boolean> {
    const result = sanitizeSettings({ ...settings });
    Object.assign(settings, result.value);

    const powerStop = parseInt(settings.power_stop, 10);
    const powerStart = parseInt(settings.power_start, 10);
    const tempStop = parseInt(settings.temperature_switch_stop, 10);
    const tempStart = parseInt(settings.temperature_switch_start, 10);
    if (
      !Number.isNaN(powerStop) &&
      !Number.isNaN(powerStart) &&
      powerStop !== 110 &&
      powerStop <= powerStart
    ) {
      showToast("停止电量必须大于恢复电量");
      return false;
    }
    if (
      settings.temperature_switch !== BinaryFlag.Off &&
      !Number.isNaN(tempStop) &&
      !Number.isNaN(tempStart) &&
      tempStop <= tempStart
    ) {
      showToast("停止温度必须大于恢复温度");
      return false;
    }
    for (const key of CONFIG_KEYS) {
      await api.setConf(key, settings[key]);
    }
    const swOk = await api.savePowerSwitches(powerSwitches.value);
    if (!swOk) {
      showToast("自定义供电开关保存失败");
      return false;
    }
    const schOk = await api.savePowerStopSchedule(powerStopSchedule.value);
    if (!schOk) {
      showToast("停充时段保存失败");
      return false;
    }
    const quietOk = await api.saveNotifyQuietSchedule(notifyQuietSchedule.value);
    if (!quietOk) {
      showToast("通知勿扰时段保存失败");
      return false;
    }
    const nightOk = await api.saveNightSchedule(nightSchedule.value);
    if (!nightOk) {
      showToast("夜间省电时段保存失败");
      return false;
    }
    if (toast) {
      if (result.fixed) showToast("已自动修正超范围配置并保存");
      else showSuccessToast("配置已保存");
    }
    return true;
  }

  async function savePowerStopSchedule(toast = true): Promise<boolean> {
    const ok = await api.savePowerStopSchedule(powerStopSchedule.value);
    if (!ok) {
      showToast("停充时段保存失败");
      return false;
    }
    powerStopSchedule.value = await api.loadPowerStopSchedule();
    if (toast) showSuccessToast("停充时段已保存");
    return true;
  }

  async function saveNotifyQuietSchedule(toast = true): Promise<boolean> {
    const ok = await api.saveNotifyQuietSchedule(notifyQuietSchedule.value);
    if (!ok) {
      showToast("通知勿扰时段保存失败");
      return false;
    }
    notifyQuietSchedule.value = await api.loadNotifyQuietSchedule();
    if (toast) showSuccessToast("勿扰时段已保存");
    return true;
  }

  async function saveNightSchedule(toast = true): Promise<boolean> {
    const ok = await api.saveNightSchedule(nightSchedule.value);
    if (!ok) {
      showToast("夜间省电时段保存失败");
      return false;
    }
    nightSchedule.value = await api.loadNightSchedule();
    if (toast) showSuccessToast("夜间时段已保存");
    return true;
  }

  async function savePowerSwitchText(toast = true): Promise<boolean> {
    const ok = await api.savePowerSwitches(powerSwitches.value);
    if (!ok) {
      showToast("自定义供电开关保存失败");
      return false;
    }
    powerSwitches.value = await api.loadPowerSwitches();
    if (toast) showSuccessToast("供电开关已保存");
    return true;
  }

  async function saveCurrent(toast = true): Promise<boolean> {
    if (!currentFeature.value) return false;
    const saved = await api.saveCurrentJsonc(current);
    if (!saved.ok) {
      showToast("电流配置保存失败");
      return false;
    }
    Object.assign(current, saved.value);
    if (toast) {
      if (saved.fixed) showToast("已自动修正超范围电流配置并保存");
      else showSuccessToast("电流控制已保存");
    }
    return true;
  }

  async function toggleModule(on: boolean): Promise<void> {
    status.moduleOn = on;
    if (on) {
      await api.exec(`rm -f '${PATHS.MODULE_OFF_FLAG}'`);
      showSuccessToast("模块已开启");
    } else {
      await api.exec(`touch '${PATHS.MODULE_OFF_FLAG}'`);
      showToast("模块已关闭");
    }
    await refreshStatus();
  }

  async function resetDefaults(): Promise<void> {
    for (const [key, value] of Object.entries(DEFAULTS) as [ConfigKey, string][]) {
      await api.setConf(key, value);
      settings[key] = value;
    }
    powerSwitches.value = [];
    powerStopSchedule.value = [];
    notifyQuietSchedule.value = [];
    nightSchedule.value = [];
    await api.savePowerSwitches([]);
    await api.savePowerStopSchedule([]);
    await api.saveNotifyQuietSchedule([]);
    await api.saveNightSchedule([]);
    if (currentFeature.value) {
      Object.assign(current, { ...CURRENT_DEFAULTS });
      const saved = await api.saveCurrentJsonc(current);
      if (saved.ok) Object.assign(current, saved.value);
    }
    showSuccessToast("已恢复默认配置");
    await refreshStatus();
  }

  return {
    loadDeviceInfo,
    loadConfig,
    loadCurrentConfig,
    saveSettings,
    savePowerStopSchedule,
    saveNotifyQuietSchedule,
    saveNightSchedule,
    savePowerSwitchText,
    saveCurrent,
    toggleModule,
    resetDefaults,
  };
}
