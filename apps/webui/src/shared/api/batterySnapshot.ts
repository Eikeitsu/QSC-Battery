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
  // 轻量 snapshot 模式，勿 source 整份 common.sh
  const result = await exec(
    `MODDIR='${PATHS.MODDIR}' sh '${PATHS.MODDIR}/bin/qsc_status.sh' snapshot`,
    8000,
    "low",
  );
  if (result.errno !== 0) return { value: EMPTY_SNAPSHOT, result };
  const body = result.stdout.replace(/^__QSC_SNAPSHOT__\r?\n?/, "");
  return { value: parseBatterySnapshot(body), result };
}
