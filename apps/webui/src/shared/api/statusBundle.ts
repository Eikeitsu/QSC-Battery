import { PATHS } from "@/shared/config/paths";
import type { ExecResult } from "@/shared/types";
import { exec, type ExecPriority } from "./ksu";
import { parseBatterySnapshot, type BatterySnapshot } from "./batterySnapshot";

export interface StatusBundle {
  snapshot: BatterySnapshot;
  moduleOff: string;
  chargingStopped: string;
  description: string;
  voltage: string;
  current: string;
  version: string;
  batteryInfo: string;
  failed: string;
}

const EMPTY_BUNDLE: StatusBundle = {
  snapshot: {
    level: "",
    temp: "",
    status: "",
    powered: false,
    source: "",
    readAt: "",
  },
  moduleOff: "",
  chargingStopped: "",
  description: "",
  voltage: "",
  current: "",
  version: "",
  batteryInfo: "",
  failed: "",
};

function section(text: string, name: string): string {
  const start = text.indexOf(`__QSC_${name}__`);
  if (start < 0) return "";
  const bodyStart = text.indexOf("\n", start);
  if (bodyStart < 0) return "";
  const next = text.indexOf("\n__QSC_", bodyStart + 1);
  return text.slice(bodyStart + 1, next < 0 ? text.length : next).trim();
}

export function parseStatusBundle(stdout: string): StatusBundle {
  return {
    snapshot: parseBatterySnapshot(section(stdout, "SNAPSHOT")),
    moduleOff: section(stdout, "MODULE_OFF"),
    chargingStopped: section(stdout, "CHARGING_STOPPED"),
    description: section(stdout, "DESCRIPTION"),
    voltage: section(stdout, "VOLTAGE"),
    current: section(stdout, "CURRENT"),
    version: section(stdout, "VERSION"),
    batteryInfo: section(stdout, "BATTERY"),
    failed: section(stdout, "FAILED"),
  };
}

export async function loadStatusBundle(priority: ExecPriority = "high"): Promise<{
  value: StatusBundle;
  result: ExecResult;
}> {
  // 复用轻量 qsc_status.sh（不 source 整份 common.sh）；轮询用 low 让交互 exec 优先
  const result = await exec(`sh '${PATHS.MODDIR}/bin/qsc_status.sh'`, 8000, priority);
  if (result.errno !== 0) return { value: EMPTY_BUNDLE, result };
  return { value: parseStatusBundle(result.stdout), result };
}
