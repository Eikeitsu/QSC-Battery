import { PATHS } from "@/shared/config/paths";
import type { ExecResult } from "@/shared/types";
import { exec } from "./ksu";
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

export async function loadStatusBundle(): Promise<{
  value: StatusBundle;
  result: ExecResult;
}> {
  const result = await exec(
    `MODDIR='${PATHS.MODDIR}'; . '${PATHS.MODDIR}/bin/common.sh' 2>/dev/null || exit 1; ` +
      `printf '__QSC_SNAPSHOT__\\n'; qsc_battery_snapshot_print; ` +
      `printf '__QSC_MODULE_OFF__\\n'; ` +
      `[ -f '${PATHS.OFF_FLAG}' ] || [ -f '${PATHS.MODDIR}/disable' ] && echo 1 || echo 0; ` +
      `printf '__QSC_CHARGING_STOPPED__\\n'; ` +
      `[ -f '${PATHS.DATADIR}/power_switch' ] && echo 1 || echo 0; ` +
      `printf '__QSC_DESCRIPTION__\\n'; ` +
      `grep '^description=' '${PATHS.MODDIR}/module.prop' 2>/dev/null | cut -d= -f2-; ` +
      `printf '__QSC_VOLTAGE__\\n'; cat /sys/class/power_supply/battery/voltage_now 2>/dev/null; ` +
      `printf '__QSC_CURRENT__\\n'; cat /sys/class/power_supply/battery/current_now 2>/dev/null; ` +
      `printf '__QSC_VERSION__\\n'; ` +
      `grep '^version=' '${PATHS.MODDIR}/module.prop' 2>/dev/null | cut -d= -f2-; ` +
      `printf '__QSC_BATTERY__\\n'; sh '${PATHS.BATTERY_INFO}' 2>/dev/null; ` +
      `printf '__QSC_FAILED__\\n'; ` +
      `[ -f '${PATHS.STOP_FAIL_HINT}' ] || [ -f '${PATHS.NO_NODE_LOGGED}' ] && echo 1 || echo 0`,
  );
  if (result.errno !== 0) return { value: EMPTY_BUNDLE, result };
  return { value: parseStatusBundle(result.stdout), result };
}
