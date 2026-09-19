import { reactive, ref } from "vue";
import { defineStore } from "pinia";
import { showToast } from "vant";
import {
  CURRENT_DEFAULTS,
  DEFAULTS,
  BadgeType,
  type CurrentConfig,
  type Settings,
  type StatusState,
} from "@/shared";
import * as api from "@/shared/api";
import { createBundleActions } from "./battery/bundleActions";
import { createConfigActions } from "./battery/configActions";
import { createLogActions } from "./battery/logActions";
import { createBatteryPlans } from "./battery/plans";
import { createStatusPolling } from "./battery/statusPolling";
import { createStatusRefresh } from "./battery/statusRefresh";

export const useAppStore = defineStore("app", () => {
  const settings = reactive<Settings>({ ...DEFAULTS });
  const current = reactive<CurrentConfig>({ ...CURRENT_DEFAULTS });
  /** 自定义供电开关：每行「路径 start=X stop=Y」 */
  const powerSwitches = ref<string[]>([]);
  /** 电量停充时段 HH:MM-HH:MM，空=全天 */
  const powerStopSchedule = ref<string[]>([]);
  /** 通知勿扰时段 */
  const notifyQuietSchedule = ref<string[]>([]);
  /** 夜间省电时段 */
  const nightSchedule = ref<string[]>([]);
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

  const statusCtx = { bridgeOk, deviceName, status };
  const { refreshStatus } = createStatusRefresh(statusCtx);

  const polling = createStatusPolling({ ready, refreshStatus });
  const { bindVisibilityListener, setInteractiveTab, startStatusPolling } = polling;

  const config = createConfigActions({
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
  });

  const bundle = createBundleActions({
    settings,
    current,
    powerSwitches,
    powerStopSchedule,
    currentFeature,
    saveSettings: config.saveSettings,
    refreshStatus,
  });

  const { refreshLog, clearLog } = createLogActions(logText, logLines, logSize);

  const plans = createBatteryPlans(settings, current, currentFeature);

  async function init(): Promise<void> {
    if (initializing.value || ready.value) return;
    initializing.value = true;
    bindVisibilityListener();
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
      await Promise.allSettled([
        config.loadDeviceInfo(),
        config.loadConfig(),
        refreshStatus(),
      ]);
      hydrating.value = true;
      void Promise.allSettled([config.loadCurrentConfig(), refreshLog()]).finally(() => {
        hydrating.value = false;
      });
    } finally {
      initializing.value = false;
      ready.value = true;
      startStatusPolling();
    }
  }

  return {
    settings,
    current,
    powerSwitches,
    powerStopSchedule,
    notifyQuietSchedule,
    nightSchedule,
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
    ...plans,
    init,
    ...config,
    ...bundle,
    setInteractiveTab,
    refreshStatus,
    refreshLog,
    clearLog,
  };
});
