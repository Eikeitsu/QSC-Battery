import { PATHS } from "@/shared";
import type { ExecResult } from "@/shared/types";
import { exec } from "./ksu";

export type BatterySnapshot = {
  level: string;
  temp: string;
  status: string;
  powered: boolean;
  source: string;
  readAt: string;
};

const EMPTY_SNAPSHOT: BatterySnapshot = {
  level: "",
  temp: "",
  status: "",
  powered: false,
  source: "",
  readAt: "",
};

export function parseBatterySnapshot(stdout: string): BatterySnapshot {
  const values = new Map<string, string>();
  for (const line of stdout.split(/\r?\n/)) {
    const separator = line.indexOf("=");
    if (separator > 0) {
      values.set(line.slice(0, separator), line.slice(separator + 1).trim());
    }
  }
  return {
    level: values.get("level") || "",
    temp: values.get("temp") || "",
    status: values.get("status") || "",
    powered: values.get("powered") === "1",
    source: values.get("source") || "",
    readAt: values.get("read_at") || "",
  };
}

export async function loadBatterySnapshot(): Promise<{
  value: BatterySnapshot;
  result: ExecResult;
}> {
  const result = await exec(
    `MODDIR='${PATHS.MODDIR}'; . '${PATHS.MODDIR}/bin/common.sh' && qsc_battery_snapshot_print`,
  );
  if (result.errno !== 0) return { value: EMPTY_SNAPSHOT, result };
  return { value: parseBatterySnapshot(result.stdout), result };
}
