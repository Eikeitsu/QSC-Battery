import { showSuccessToast, showToast } from "vant";
import { BinaryFlag, BadgeType, type StatusState } from "@/shared";
import * as api from "@/shared/api";
import type { Ref } from "vue";

export type StatusRefreshCtx = {
  bridgeOk: Ref<boolean>;
  deviceName: Ref<string>;
  status: StatusState;
};

export async function refreshStatusInternal(ctx: StatusRefreshCtx): Promise<boolean> {
  const { bridgeOk, deviceName, status } = ctx;

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

export function createStatusRefresh(ctx: StatusRefreshCtx) {
  let refreshInFlight: Promise<boolean> | null = null;
  let refreshTipPending = false;

  async function refreshStatus(showTip = false): Promise<void> {
    if (showTip) refreshTipPending = true;
    if (refreshInFlight) {
      await refreshInFlight;
      return;
    }

    const request = refreshStatusInternal(ctx);
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

  return { refreshStatus };
}
