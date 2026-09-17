import { showSuccessToast, showToast } from "vant";
import { DEFAULTS, type CurrentConfig, type Settings } from "@/shared";
import * as api from "@/shared/api";
import type { Ref } from "vue";

export type BundleActionsCtx = {
  settings: Settings;
  current: CurrentConfig;
  powerSwitches: Ref<string[]>;
  powerStopSchedule: Ref<string[]>;
  currentFeature: Ref<boolean>;
  saveSettings: (toast?: boolean) => Promise<boolean>;
  refreshStatus: () => Promise<void>;
};

export function createBundleActions(ctx: BundleActionsCtx) {
  const {
    settings,
    current,
    powerSwitches,
    powerStopSchedule,
    currentFeature,
    saveSettings,
    refreshStatus,
  } = ctx;

  function snapshotBundle(): api.ConfigBundle {
    return {
      version: 1,
      settings: { ...settings },
      power_switches: [...powerSwitches.value],
      power_stop_schedule: [...powerStopSchedule.value],
      current: currentFeature.value ? { ...current } : null,
      device_profile: null,
    };
  }

  async function snapshotBundleAsync(): Promise<api.ConfigBundle> {
    const bundle = snapshotBundle();
    bundle.device_profile = await api.loadDeviceProfileExport();
    return bundle;
  }

  async function applyBundle(bundle: api.ConfigBundle, toast = true): Promise<boolean> {
    Object.assign(settings, { ...DEFAULTS, ...bundle.settings });
    powerSwitches.value = [...(bundle.power_switches || [])];
    powerStopSchedule.value = [...(bundle.power_stop_schedule || [])];
    const ok = await saveSettings(false);
    if (!ok) return false;
    if (currentFeature.value && bundle.current) {
      Object.assign(current, bundle.current);
      const saved = await api.saveCurrentJsonc(current);
      if (!saved.ok) {
        showToast("电流配置导入失败");
        return false;
      }
      Object.assign(current, saved.value);
    }
    if (bundle.device_profile) {
      await api.applyDeviceProfileExport(bundle.device_profile);
    }
    if (toast) showSuccessToast("配置已应用");
    await refreshStatus();
    return true;
  }

  async function exportConfig(): Promise<boolean> {
    const ok = await api.exportConfigBundle(await snapshotBundleAsync());
    if (ok) showSuccessToast("已导出到 Download/qsc_battery_config.json");
    else showToast("导出失败");
    return ok;
  }

  async function importConfig(): Promise<boolean> {
    const bundle = await api.importConfigBundle();
    if (!bundle) {
      showToast("未找到 Download/qsc_battery_config.json");
      return false;
    }
    return applyBundle(bundle);
  }

  return {
    snapshotBundle,
    snapshotBundleAsync,
    applyBundle,
    exportConfig,
    importConfig,
  };
}
