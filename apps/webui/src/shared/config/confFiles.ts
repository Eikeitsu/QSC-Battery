/** 配置键落在哪个文件（与模块 conf_migrate.sh 对齐） */
export const POWER_CONF_KEYS = [
  "power_saver",
  "power_profile",
  "screen_off_saver",
  "night_saver",
  "deep_idle_enable",
  "deep_after_sec",
  "deep_idle_sec",
  "deep_full_gap_sec",
  "heartbeat_sec",
  "screen_probe_dumpsys",
  "loop_interval_sec",
  "loop_interval_maintain_sec",
  "loop_interval_idle_sec",
  "loop_interval_idle_native_sec",
  "loop_interval_plugged_sec",
  "loop_interval_plugged_native_sec",
  "loop_interval_near_window",
  "native_daemon",
  "native_impl",
  "description_enable",
  "stop_hold_wakelock",
] as const;

export const NOTIFY_CONF_KEYS = [
  "notify_charge_event",
  "notify_charge_kinds",
  "notify_power_status",
] as const;

const POWER_SET = new Set<string>(POWER_CONF_KEYS);
const NOTIFY_SET = new Set<string>(NOTIFY_CONF_KEYS);

export type ConfFileKind = "config" | "power" | "notify";

export function confFileForKey(key: string): ConfFileKind {
  if (POWER_SET.has(key)) return "power";
  if (NOTIFY_SET.has(key)) return "notify";
  return "config";
}
