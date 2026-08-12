import { computed, reactive, ref } from "vue";
import { defineStore } from "pinia";
import { showSuccessToast, showToast } from "vant";
import {
  CONFIG_KEYS,
  CURRENT_DEFAULTS,
  DEFAULTS,
  PATHS,
  STATUS_INTERVAL,
  sanitizeSettings,
  type BadgeType,
  type ConfigKey,
  type CurrentConfig,
  type Settings,
  type StatusState,
} from "@/shared";
import * as api from "@/shared/api";

export const useAppStore = defineStore("app", () => {
  const settings = reactive<Settings>({ ...DEFAULTS });
  const current = reactive<CurrentConfig>({ ...CURRENT_DEFAULTS });
  const currentFeature = ref(false);
  const bridgeOk = ref(false);
  const deviceName = ref("加载中…");
  const status = reactive<StatusState>({
    level: "--",
    temp: "--",
    badge: "状态加载中…",
    badgeType: "default",
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

  let statusTimer: ReturnType<typeof setInterval> | null = null;

  const powerPlan = computed(() => {
    const stop = settings.power_stop;
    const start = settings.power_start;
    if (String(stop) === "110") return "已关闭";
    return `停充 ≥${stop}% · 恢复 ≤${start}%`;
  });

  const tempPlan = computed(() => {
    if (settings.temperature_switch === "0") return "已关闭";
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

  const fullPlan = computed(() => (settings.charge_full === "1" ? "已开启" : "已关闭"));
  const resetPlan = computed(() => (settings.power_reset === "1" ? "已开启" : "已关闭"));
  const compatPlan = computed(() =>
    settings.Compatibility_mode === "1" ? "已开启" : "已关闭",
  );

  async function loadDeviceInfo(): Promise<void> {
    if (!api.hasBridge()) {
      deviceName.value = "WebUI 桥接不可用";
      return;
    }
    const model = await api.exec(
      `getprop ro.product.marketname 2>/dev/null || getprop ro.product.model 2>/dev/null`,
    );
    const os = await api.exec(
      `getprop ro.mi.os.version.incremental 2>/dev/null | sed 's/^OS//'`,
    );
    const modelName = model.stdout.trim() || "Android";
    const osName = os.stdout.trim();
    deviceName.value = osName ? `${modelName} · HyperOS ${osName}` : modelName;
  }

  async function loadConfig(): Promise<void> {
    for (const key of CONFIG_KEYS) {
      const value = await api.getConf(key);
      settings[key] = value || DEFAULTS[key];
    }
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
      settings.temperature_switch !== "0" &&
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
    if (toast) {
      if (result.fixed) showToast("已自动修正超范围配置并保存");
      else showSuccessToast("配置已保存");
    }
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
    if (currentFeature.value) {
      Object.assign(current, { ...CURRENT_DEFAULTS });
      const saved = await api.saveCurrentJsonc(current);
      if (saved.ok) Object.assign(current, saved.value);
    }
    showSuccessToast("已恢复默认配置");
    await refreshStatus();
  }

  async function refreshStatus(showTip = false): Promise<void> {
    if (!api.hasBridge()) {
      bridgeOk.value = false;
      deviceName.value = "未检测到 WebUI 桥接";
      status.badge = "请用 KernelSU 等支持 WebUI 的管理器打开";
      status.badgeType = "danger";
      return;
    }

    const [capR, tempR, offR, switchR, descR, statusR, voltR, currR, verR, battR] =
      await Promise.all([
        api.exec(
          `cat /sys/class/power_supply/battery/capacity 2>/dev/null || cat /sys/class/power_supply/bms/capacity 2>/dev/null`,
        ),
        api.exec(
          `cat /sys/class/power_supply/battery/temp 2>/dev/null || cat /sys/class/power_supply/bms/temp 2>/dev/null`,
        ),
        api.exec(
          `[ -f '${PATHS.OFF_FLAG}' ] || [ -f '${PATHS.MODDIR}/disable' ] && echo 1 || echo 0`,
        ),
        api.exec(`[ -f '${PATHS.DATADIR}/power_switch' ] && echo 1 || echo 0`),
        api.exec(
          `grep '^description=' '${PATHS.MODDIR}/module.prop' 2>/dev/null | cut -d= -f2-`,
        ),
        api.exec(`cat /sys/class/power_supply/battery/status 2>/dev/null`),
        api.exec(`cat /sys/class/power_supply/battery/voltage_now 2>/dev/null`),
        api.exec(`cat /sys/class/power_supply/battery/current_now 2>/dev/null`),
        api.exec(
          `grep '^version=' '${PATHS.MODDIR}/module.prop' 2>/dev/null | cut -d= -f2-`,
        ),
        api.exec(`sh '${PATHS.BATTERY_INFO}' 2>/dev/null`),
      ]);

    if (capR.errno === -2 || tempR.errno === -2) {
      status.badge = "状态读取超时，下拉重试";
      status.badgeType = "warning";
      if (showTip) showToast("状态读取超时");
      return;
    }

    bridgeOk.value = true;
    const level = capR.stdout.trim();
    const rawTemp = parseInt(tempR.stdout.trim(), 10);
    const tempC = Number.isNaN(rawTemp)
      ? null
      : rawTemp > 200
        ? Math.round(rawTemp / 10)
        : rawTemp;
    const moduleOff = offR.stdout.trim() === "1";
    const chargingStopped = switchR.stdout.trim() === "1";
    const chargeStatus = statusR.stdout.trim();

    status.level = level || "--";
    status.temp = tempC !== null ? String(tempC) : "--";
    status.moduleOn = !moduleOff;

    const descRaw = descR.stdout.trim();
    const bracket = descRaw.match(/\[([^\]]+)\]/);
    const bracketBody = bracket ? bracket[1].trim() : "";
    const [majorPart, ...innerParts] = bracketBody ? bracketBody.split("|") : [""];
    const majorDesc = (majorPart || "").trim();
    const innerDesc = innerParts.join("|").trim();
    const restDesc = descRaw.replace(/\[[^\]]*\]\s*/, "").trim();
    const bits = [innerDesc, restDesc].filter(Boolean);
    if (bits.length) status.desc = bits.join(" · ");

    let badgeType: BadgeType = "primary";
    if (moduleOff) {
      status.badge = majorDesc || "模块已关闭";
      badgeType = "danger";
    } else if (chargingStopped) {
      status.badge = majorDesc || "已停充，等待恢复";
      badgeType = "warning";
    } else if (chargeStatus === "Charging" || chargeStatus === "Full") {
      status.badge = majorDesc || "充电中";
      badgeType = "success";
    } else {
      status.badge = majorDesc || "未充电";
      badgeType = "primary";
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

    const voltRaw = parseInt(voltR.stdout.trim(), 10);
    status.voltage = Number.isNaN(voltRaw)
      ? "--"
      : voltRaw > 100000
        ? (voltRaw / 1000000).toFixed(2)
        : (voltRaw / 1000).toFixed(2);

    const currRaw = parseInt(currR.stdout.trim(), 10);
    status.currentMa = Number.isNaN(currRaw)
      ? "--"
      : String(Math.round(Math.abs(currRaw) > 10000 ? currRaw / 1000 : currRaw));

    status.version = verR.stdout.trim() || "--";

    const battMap: Record<string, string> = {};
    for (const line of battR.stdout.split("\n")) {
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

    if (showTip) showSuccessToast("状态已刷新");
  }

  async function refreshLog(showTip = false): Promise<void> {
    const [logR, sizeR] = await Promise.all([
      api.exec(`tail -n 50 '${PATHS.LOG_FILE}' 2>/dev/null`),
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
    if (!api.hasBridge()) {
      bridgeOk.value = false;
      deviceName.value = "未检测到 WebUI 桥接";
      status.badge = "当前环境无法执行 shell";
      status.badgeType = "danger";
      showToast("请使用支持 WebUI 的管理器打开");
      return;
    }
    await Promise.allSettled([
      loadDeviceInfo(),
      loadConfig(),
      loadCurrentConfig(),
      refreshStatus(),
      refreshLog(),
    ]);
    if (statusTimer) clearInterval(statusTimer);
    statusTimer = setInterval(() => {
      void refreshStatus();
    }, STATUS_INTERVAL);
  }

  return {
    settings,
    current,
    currentFeature,
    bridgeOk,
    deviceName,
    status,
    logText,
    logLines,
    logSize,
    powerPlan,
    tempPlan,
    currentPlan,
    fullPlan,
    resetPlan,
    compatPlan,
    init,
    saveSettings,
    saveCurrent,
    toggleModule,
    resetDefaults,
    refreshStatus,
    refreshLog,
    clearLog,
  };
});
