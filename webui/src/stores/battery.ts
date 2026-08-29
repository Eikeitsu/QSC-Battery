import { computed, reactive, ref } from "vue";
import { defineStore } from "pinia";
import { showSuccessToast, showToast } from "vant";
import {
  CONFIG_KEYS,
  CURRENT_DEFAULTS,
  DEFAULTS,
  DEVICE_INFO_SHELL,
  PATHS,
  STATUS_INTERVAL,
  formatDeviceLabel,
  sanitizeSettings,
  BadgeType,
  BinaryFlag,
  type ConfigKey,
  type CurrentConfig,
  type Settings,
  type StatusState,
} from "@/shared";
import * as api from "@/shared/api";

export const useAppStore = defineStore("app", () => {
  const settings = reactive<Settings>({ ...DEFAULTS });
  const current = reactive<CurrentConfig>({ ...CURRENT_DEFAULTS });
  /** 自定义供电开关：每行「路径 start=X stop=Y」 */
  const powerSwitches = ref<string[]>([]);
  /** 电量停充时段 HH:MM-HH:MM，空=全天 */
  const powerStopSchedule = ref<string[]>([]);
  /** 通知勿扰时段 */
  const notifyQuietSchedule = ref<string[]>([]);
  const currentFeature = ref(false);
  const bridgeOk = ref(false);
  const deviceName = ref("加载中…");
  const status = reactive<StatusState>({
    level: "--",
    temp: "--",
    badge: "状态加载中…",
    badgeType: BadgeType.Default,
    desc: "电量/温度停充；若安装了电流控制，可在配置页调节。",
    chargeLabel: "--",
    voltage: "--",
    currentMa: "--",
    version: "--",
    updatedAt: "--",
    moduleOn: true,
    health: "--",
    soh: "--",
    designMah: "--",
    fullMah: "--",
    cycleCount: "--",
  });
  const logText = ref("暂无日志");
  const logLines = ref(0);
  const logSize = ref("--");
  const initializing = ref(false);
  const hydrating = ref(false);
  const ready = ref(false);

  let statusTimer: ReturnType<typeof setInterval> | null = null;
  let refreshInFlight: Promise<boolean> | null = null;
  let refreshTipPending = false;

  const powerPlan = computed(() => {
    const stop = settings.power_stop;
    const start = settings.power_start;
    if (String(stop) === "110") return "已关闭";
    return `停充 ≥${stop}% · 恢复 ≤${start}%`;
  });

  const tempPlan = computed(() => {
    if (settings.temperature_switch === BinaryFlag.Off) return "已关闭";
    return `停充 ≥${settings.temperature_switch_stop}°C · 恢复 ≤${settings.temperature_switch_start}°C`;
  });

  const currentPlan = computed(() => {
    if (!currentFeature.value) return "--";
    if (!Number(current.current_control)) return "已关闭";
    const parts = ["已开启"];
    if (Number(current.bypass_enable)) {
      if (Number(current.battery_stop) <= 100)
        parts.push(`旁路≥${current.battery_stop}%`);
      if (Number(current.bypass_temp) <= 100) parts.push(`旁路≥${current.bypass_temp}°C`);
      if ((current.bypass_schedule || []).length) parts.push("旁路时段");
    }
    if (Number(current.slow_charge) <= 100) parts.push(`慢充≥${current.slow_charge}%`);
    if (Number(current.temperature_current)) parts.push("温控限流");
    if (Number(current.app_limit)) parts.push("游戏限流");
    return parts.join(" · ");
  });

  const fullPlan = computed(() =>
    settings.charge_full === BinaryFlag.On ? "已开启" : "已关闭",
  );
  const resetPlan = computed(() =>
    settings.power_reset === BinaryFlag.On ? "已开启" : "已关闭",
  );
  const compatPlan = computed(() =>
    settings.Compatibility_mode === BinaryFlag.On ? "已开启" : "已关闭",
  );

  async function loadDeviceInfo(): Promise<void> {
    if (!api.hasBridge()) {
      deviceName.value = "WebUI 桥接不可用";
      return;
    }
    const info = await api.exec(DEVICE_INFO_SHELL);
    deviceName.value = formatDeviceLabel(info.stdout);
  }

  async function loadConfig(): Promise<void> {
    const [values, switches, stopSchedule, quietSchedule] = await Promise.all([
      api.loadConfigValues(CONFIG_KEYS),
      api.loadPowerSwitches(),
      api.loadPowerStopSchedule(),
      api.loadNotifyQuietSchedule(),
    ]);
    CONFIG_KEYS.forEach((key) => {
      settings[key] = values[key] || DEFAULTS[key];
    });
    powerSwitches.value = switches;
    powerStopSchedule.value = stopSchedule;
    notifyQuietSchedule.value = quietSchedule;
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
      await api.exec(`rm -f '${PATHS.OFF_FLAG}'`);
      showSuccessToast("模块已开启");
    } else {
      await api.exec(`touch '${PATHS.OFF_FLAG}'`);
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
    await api.savePowerSwitches([]);
    await api.savePowerStopSchedule([]);
    await api.saveNotifyQuietSchedule([]);
    if (currentFeature.value) {
      Object.assign(current, { ...CURRENT_DEFAULTS });
      const saved = await api.saveCurrentJsonc(current);
      if (saved.ok) Object.assign(current, saved.value);
    }
    showSuccessToast("已恢复默认配置");
    await refreshStatus();
  }

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

  async function refreshStatusInternal(): Promise<boolean> {
    if (!api.hasBridge()) {
      bridgeOk.value = false;
      deviceName.value = "未检测到 WebUI 桥接";
      status.badge = "请用 KernelSU 等支持 WebUI 的管理器打开";
      status.badgeType = BadgeType.Danger;
      return false;
    }

    const { value: bundle, result: statusResult } = await api.loadStatusBundle();

    if (statusResult.errno === -2) {
      status.badge = "状态读取超时，下拉重试";
      status.badgeType = BadgeType.Warning;
      return false;
    }

    bridgeOk.value = true;
    const level = bundle.snapshot.level;
    const rawTemp = parseInt(bundle.snapshot.temp, 10);
    const tempC = Number.isNaN(rawTemp)
      ? null
      : rawTemp > 200
        ? Math.round(rawTemp / 10)
        : rawTemp;
    const moduleOff = bundle.moduleOff === BinaryFlag.On;
    const chargingStopped = bundle.chargingStopped === BinaryFlag.On;
    const chargeStatus =
      bundle.snapshot.status === "2"
        ? "Charging"
        : bundle.snapshot.status === "5"
          ? "Full"
          : bundle.snapshot.status === "3"
            ? "Discharging"
            : bundle.snapshot.status === "4"
              ? "Not charging"
              : bundle.snapshot.status;

    status.level = level || "--";
    status.temp = tempC !== null ? String(tempC) : "--";
    status.moduleOn = !moduleOff;

    const descRaw = bundle.description;
    const bracket = descRaw.match(/\[([^\]]+)\]/);
    const bracketBody = bracket ? bracket[1].trim() : "";
    const [majorPart, ...innerParts] = bracketBody ? bracketBody.split("|") : [""];
    const majorDesc = (majorPart || "").trim();
    const innerDesc = innerParts.join("|").trim();
    const restDesc = descRaw.replace(/\[[^\]]*\]\s*/, "").trim();
    const bits = [innerDesc, restDesc].filter(Boolean);
    if (bits.length) status.desc = bits.join(" · ");

    let badgeType: BadgeType = BadgeType.Primary;
    if (moduleOff) {
      status.badge = majorDesc || "模块已关闭";
      badgeType = BadgeType.Danger;
    } else if (chargingStopped) {
      status.badge = majorDesc || "已停充，等待恢复";
      badgeType = BadgeType.Warning;
    } else if (bundle.failed === BinaryFlag.On) {
      status.badge = majorDesc || "停充可能未生效";
      badgeType = BadgeType.Warning;
      status.desc = "请插电后 Action 音量下测开关，或到「策略 → 测开关与缓存」清除后重启";
    } else if (chargeStatus === "Charging" || chargeStatus === "Full") {
      status.badge = majorDesc || "充电中";
      badgeType = BadgeType.Success;
    } else {
      status.badge = majorDesc || "未充电";
      badgeType = BadgeType.Primary;
    }
    status.badgeType = badgeType;

    const statusMap: Record<string, string> = {
      Charging: "充电中",
      Full: "已充满",
      Discharging: "未充电",
      "Not charging": "未充电",
      Unknown: "未知",
    };
    if (moduleOff) status.chargeLabel = "模块关";
    else if (chargingStopped) status.chargeLabel = "已停充";
    else status.chargeLabel = statusMap[chargeStatus] || chargeStatus || "--";

    const voltRaw = parseInt(bundle.voltage, 10);
    status.voltage = Number.isNaN(voltRaw)
      ? "--"
      : voltRaw > 100000
        ? (voltRaw / 1000000).toFixed(2)
        : (voltRaw / 1000).toFixed(2);

    const currRaw = parseInt(bundle.current, 10);
    status.currentMa = Number.isNaN(currRaw)
      ? "--"
      : String(Math.round(Math.abs(currRaw) > 10000 ? currRaw / 1000 : currRaw));

    status.version = bundle.version || "--";

    const battMap: Record<string, string> = {};
    for (const line of bundle.batteryInfo.split("\n")) {
      const i = line.indexOf("=");
      if (i <= 0) continue;
      battMap[line.slice(0, i).trim()] = line.slice(i + 1).trim();
    }
    status.health = battMap.health || "--";
    status.soh = battMap.soh || "--";
    status.designMah = battMap.design_mah || "--";
    status.fullMah = battMap.full_mah || "--";
    status.cycleCount = battMap.cycle_count || "--";

    const now = new Date();
    status.updatedAt = [
      String(now.getHours()).padStart(2, "0"),
      String(now.getMinutes()).padStart(2, "0"),
      String(now.getSeconds()).padStart(2, "0"),
    ].join(":");

    return true;
  }

  async function refreshStatus(showTip = false): Promise<void> {
    if (showTip) refreshTipPending = true;
    if (refreshInFlight) {
      await refreshInFlight;
      return;
    }

    const request = refreshStatusInternal();
    refreshInFlight = request;
    try {
      const ok = await request;
      if (refreshTipPending) {
        refreshTipPending = false;
        if (ok) showSuccessToast({ message: "状态已刷新", duration: 1200 });
        else showToast("状态读取超时");
      }
    } catch {
      if (refreshTipPending) {
        refreshTipPending = false;
        showToast("状态读取失败");
      }
    } finally {
      if (refreshInFlight === request) refreshInFlight = null;
    }
  }

  async function refreshLog(showTip = false): Promise<void> {
    const [logR, sizeR] = await Promise.all([
      api.exec(`tail -n 80 '${PATHS.LOG_FILE}' 2>/dev/null`),
      api.exec(`wc -c < '${PATHS.LOG_FILE}' 2>/dev/null`),
    ]);
    const text = logR.stdout.trim();
    logText.value = text || "暂无日志（触发功能后才会写入）";
    logLines.value = text ? text.split("\n").filter(Boolean).length : 0;
    const sizeRaw = parseInt(sizeR.stdout.trim(), 10);
    if (Number.isNaN(sizeRaw)) logSize.value = "--";
    else if (sizeRaw < 1024) logSize.value = `${sizeRaw} B`;
    else if (sizeRaw < 1024 * 1024) logSize.value = `${(sizeRaw / 1024).toFixed(1)} KB`;
    else logSize.value = `${(sizeRaw / 1024 / 1024).toFixed(2)} MB`;
    if (!showTip) return;
    if (logR.errno === -2) showToast("日志读取超时");
    else showSuccessToast("日志已刷新");
  }

  async function clearLog(): Promise<void> {
    await api.exec(`: > '${PATHS.LOG_FILE}'`);
    await refreshLog(false);
    showSuccessToast("日志已清空");
  }

  async function init(): Promise<void> {
    if (initializing.value || ready.value) return;
    initializing.value = true;
    if (!api.hasBridge()) {
      bridgeOk.value = false;
      deviceName.value = "未检测到 WebUI 桥接";
      status.badge = "当前环境无法执行 shell";
      status.badgeType = BadgeType.Danger;
      showToast("请使用支持 WebUI 的管理器打开");
      initializing.value = false;
      ready.value = true;
      return;
    }
    try {
      // 先完成首页和策略页需要的核心数据，日志与可选电流配置后台加载。
      await Promise.allSettled([loadDeviceInfo(), loadConfig(), refreshStatus()]);
      if (statusTimer) clearInterval(statusTimer);
      statusTimer = setInterval(() => {
        void refreshStatus();
      }, STATUS_INTERVAL);
      hydrating.value = true;
      void Promise.allSettled([loadCurrentConfig(), refreshLog()]).finally(() => {
        hydrating.value = false;
      });
    } finally {
      initializing.value = false;
      ready.value = true;
    }
  }

  return {
    settings,
    current,
    powerSwitches,
    powerStopSchedule,
    notifyQuietSchedule,
    currentFeature,
    bridgeOk,
    deviceName,
    status,
    logText,
    logLines,
    logSize,
    initializing,
    hydrating,
    ready,
    powerPlan,
    tempPlan,
    currentPlan,
    fullPlan,
    resetPlan,
    compatPlan,
    init,
    saveSettings,
    savePowerSwitchText,
    savePowerStopSchedule,
    saveNotifyQuietSchedule,
    saveCurrent,
    toggleModule,
    resetDefaults,
    snapshotBundle,
    snapshotBundleAsync,
    applyBundle,
    exportConfig,
    importConfig,
    refreshStatus,
    refreshLog,
    clearLog,
  };
});
